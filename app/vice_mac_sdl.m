/* vice_mac_sdl.m
 * macOS platform arch layer for c=foundation.
 * Implements VICE's uiapi.h, vsyncapi.h, and videoarch.h contracts.
 *
 * This is the central arch file, analogous to atari_mac_sdl.c in fuji-foundation.
 * It replaces everything under vice/src/arch/sdl/.
 *
 * Phase 2: NSWindow + VICEMetalView wired; NSEvent queue drained on VICE thread.
 *
 * Threading: with USE_VICE_THREAD, VICE runs in its own pthread.
 * video_canvas_refresh() and vsyncarch_presync() are called on the VICE thread.
 * All AppKit and Metal calls must be dispatched to the main thread.
 *
 * Compiled as Objective-C (.m) to allow direct AppKit/NSEvent usage.
 * All VICE C headers compile cleanly under ObjC (it is a superset of C99).
 */

#import <AppKit/AppKit.h>
#import <dispatch/dispatch.h>

#import "VICEStatusBridge.h"
#import "VICEEngine.h"

#include "vice_mac_sdl.h"
#include "vice_mac_kbd.h"
#include "vice_mac_joystick.h"
#include "vice_net2iec.h"
#include "vice_config.h"

/* VICE core headers */
#include "lib.h"
#include "log.h"
#include "uiapi.h"
#include "vsyncapi.h"
#include "videoarch.h"
#include "resources.h"
#include "mainlock.h"
#include "fullscreen.h"
#include "types.h"
#include "uiactions.h"
#include "main.h"
#include "palette.h"
#include "video.h"
#include "vsync.h"
#include "archdep_tick.h"
#include "keyboard.h"
#include "keymap.h"

#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <string.h>

/* C bridge to VICEDisplayManager (defined in VICEDisplayManager.m) */
extern void Vice_DisplayManagerDidReceiveFrame(const uint32_t *argbPixels,
                                               int width, int height, int rowPitch);

/* C bridges into ObjC layer (defined in VICEMetalView.m) */
extern void Vice_MetalViewCreate(void *nsWindow, int width, int height);
extern void Vice_MetalViewSetDisplayManager(void);
extern void Vice_MetalViewDestroy(void);

/* ── Static state ──────────────────────────────────────────────────────── */

static log_t vice_mac_log = LOG_DEFAULT;

/* Emulator window — set in vice_mac_ui_init so we can check window focus. */
static NSWindow *gEmulatorWindow = nil;

/* ── Keyboard event buffer ───────────────────────────────────────────────
 * NSEvent addLocalMonitorForEventsMatchingMask: captures key events on the
 * main thread as they arrive from the window server.  We push them into a
 * small circular buffer that the VICE thread drains each frame.
 *
 * This replaces the earlier dispatch_sync drain approach, which missed
 * events because window-server port reads happen later in the run loop
 * iteration than the dispatch queue drains. */

#define KBD_QUEUE_SIZE 128

typedef struct {
    uint16_t keyCode;
    uint32_t modifiers;
    int      down;      /* 1 = press, 0 = release, -1 = FlagsChanged */
} VICEKeyEvent;

static VICEKeyEvent  s_kbdQueue[KBD_QUEUE_SIZE];
static volatile int  s_kbdHead = 0;   /* writer index (main thread) */
static volatile int  s_kbdTail = 0;   /* reader index (VICE thread) */
static os_unfair_lock s_kbdLock = OS_UNFAIR_LOCK_INIT;

static void _kbd_push(uint16_t keyCode, uint32_t modifiers, int down) {
    os_unfair_lock_lock(&s_kbdLock);
    int next = (s_kbdHead + 1) % KBD_QUEUE_SIZE;
    if (next != s_kbdTail) {          /* drop if full (very unlikely at 128) */
        s_kbdQueue[s_kbdHead] = (VICEKeyEvent){ keyCode, modifiers, down };
        s_kbdHead = next;
    }
    os_unfair_lock_unlock(&s_kbdLock);
}

/* Drain and dispatch all pending key events.  Called on the VICE thread
 * from vsyncarch_presync() while the VICE main lock is held. */
static void _kbd_drain(void) {
    while (1) {
        os_unfair_lock_lock(&s_kbdLock);
        if (s_kbdTail == s_kbdHead) {
            os_unfair_lock_unlock(&s_kbdLock);
            break;
        }
        VICEKeyEvent ev = s_kbdQueue[s_kbdTail];
        s_kbdTail = (s_kbdTail + 1) % KBD_QUEUE_SIZE;
        os_unfair_lock_unlock(&s_kbdLock);

        if (ev.down == -1) {
            vice_mac_modifier_event(ev.keyCode, ev.modifiers);
        } else {
            vice_mac_key_event(ev.keyCode, ev.modifiers, ev.down);
        }
    }
}

/* C64 frame dimensions — override via video_canvas_create if VICE reports different */
#define VICE_MAC_CANVAS_W   384
#define VICE_MAC_CANVAS_H   272

/* ── archdep override ───────────────────────────────────────────────────── */

char *archdep_get_vice_datadir(void) {
    return vice_mac_get_vice_datadir();
}

char *vice_mac_get_vice_datadir(void) {
    CFURLRef resURL = CFBundleCopyResourcesDirectoryURL(CFBundleGetMainBundle());
    if (!resURL) return lib_strdup("/usr/local/share/vice");

    char respath[4096];
    CFURLGetFileSystemRepresentation(resURL, true,
                                     (uint8_t *)respath, sizeof(respath));
    CFRelease(resURL);

    const char *suffix = "/vice-data";
    char *result = lib_malloc(strlen(respath) + strlen(suffix) + 1);
    sprintf(result, "%s%s", respath, suffix);
    return result;
}

/* ── uiapi.h implementation ─────────────────────────────────────────────── */

int ui_resources_init(void)     { return 0; }
int ui_cmdline_options_init(void) { return 0; }

int ui_init(void) {
    return vice_mac_ui_init();
}

int ui_init_finalize(void) {
    vice_mac_log = log_open("VICEMacUI");
    vice_mac_kbd_init();
    vice_mac_joystick_init();
    vice_net2iec_init();

    /* Override keymap resources so keyboard_key_pressed() can translate
     * X11/GDK key symbols → C64 matrix row/column.
     *
     * The headless arch constructs "headless_sym.vkm" as the default keymap
     * name, which doesn't exist.  KeymapIndex 0/1 (sym/pos) go through
     * switch_keymap_file() which also generates "headless_*.vkm" names and
     * fails.  Using KeymapIndex 2 (KBD_INDEX_USERSYM) skips that check and
     * loads the resource value directly.  gtk3_sym.vkm uses the same
     * X11/GDK keysyms our static keycode table emits. */
    resources_set_string("KeymapUserSymFile", "gtk3_sym.vkm");
    resources_set_int("KeymapIndex", KBD_INDEX_USERSYM);

    /* Install a local event monitor so key events are captured on the main
     * thread as soon as they arrive from the window server.  Events are
     * pushed into the circular buffer above and drained by the VICE thread
     * each frame.  Return nil to consume emulator-bound events so they don't
     * also propagate through the responder chain. */
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSEvent addLocalMonitorForEventsMatchingMask:
             (NSEventMaskKeyDown | NSEventMaskKeyUp | NSEventMaskFlagsChanged)
             handler:^NSEvent *(NSEvent *event) {
            if (!gEmulatorWindow || !gEmulatorWindow.isKeyWindow) {
                return event; /* pass through to other windows */
            }
            if (event.type == NSEventTypeKeyDown) {
                _kbd_push((uint16_t)event.keyCode,
                          (uint32_t)event.modifierFlags, 1);
                return nil;  /* consume */
            }
            if (event.type == NSEventTypeKeyUp) {
                _kbd_push((uint16_t)event.keyCode,
                          (uint32_t)event.modifierFlags, 0);
                return nil;
            }
            if (event.type == NSEventTypeFlagsChanged) {
                _kbd_push((uint16_t)event.keyCode,
                          (uint32_t)event.modifierFlags, -1);
                return nil;
            }
            return event;
        }];
    });

    log_message(vice_mac_log, "c=foundation macOS UI initialised.");
    return 0;
}

void ui_shutdown(void) {
    vice_mac_ui_shutdown();
}

/* Non-fatal message — dispatch to main thread for NSAlert */
void ui_message(const char *format, ...) {
    char buf[1024];
    va_list args;
    va_start(args, format);
    vsnprintf(buf, sizeof(buf), format, args);
    va_end(args);
    vice_mac_ui_message(buf);
}

/* Error message */
void ui_error(const char *format, ...) {
    char buf[1024];
    va_list args;
    va_start(args, format);
    vsnprintf(buf, sizeof(buf), format, args);
    va_end(args);
    vice_mac_ui_error(buf);
}

/* Drive LED */
void ui_display_drive_led(unsigned int drive, unsigned int base,
                          unsigned int pwm1, unsigned int pwm2) {
    vice_mac_ui_set_drive_led(drive + base, 0, pwm1);
}

/* Drive track */
void ui_display_drive_track(unsigned int drive, unsigned int base,
                             unsigned int half_track, unsigned int side) {
    vice_mac_ui_set_drive_track(drive + base, half_track);
}

/* Forward declarations for pause API (defined later in this file; called
 * from ui_jam_dialog before the definitions appear). */
extern void ui_pause_enable(void);
extern void ui_pause_disable(void);

/* JAM dialog — pause the emulator and show a modal alert.
 * Called on the VICE thread; uses dispatch_async so it doesn't block VICE.
 * The emulator is paused via ui_pause_enable() to stop the JAM flood while
 * the alert is open. */
static volatile int s_jam_shown = 0;

ui_jam_action_t ui_jam_dialog(const char *format, ...) {
    char buf[1024];
    va_list args;
    va_start(args, format);
    vsnprintf(buf, sizeof(buf), format, args);
    va_end(args);
    log_error(vice_mac_log, "CPU JAM: %s", buf);

    /* Prevent multiple simultaneous dialogs */
    if (__sync_val_compare_and_swap(&s_jam_shown, 0, 1) != 0) {
        return UI_JAM_NONE;
    }

    /* Freeze the emulator so it stops re-JAMming while the alert is shown */
    ui_pause_enable();

    NSString *msg = [NSString stringWithUTF8String:buf];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert      = [[NSAlert alloc] init];
        alert.messageText   = @"CPU JAM";
        alert.informativeText = [NSString stringWithFormat:
                                 @"The CPU has halted.\n\n%@", msg];
        alert.alertStyle    = NSAlertStyleCritical;
        [alert addButtonWithTitle:@"Reset"];
        [alert addButtonWithTitle:@"Hard Reset"];
        [alert addButtonWithTitle:@"Continue"];

        NSModalResponse resp = [alert runModal];

        if (resp == NSAlertFirstButtonReturn) {
            [[VICEEngine sharedEngine] reset:VICEResetModeSoft];
        } else if (resp == NSAlertSecondButtonReturn) {
            [[VICEEngine sharedEngine] reset:VICEResetModeHard];
        }
        /* All responses: unpause (reset also clears JAM state) */
        [VICEEngine sharedEngine].pauseEnabled = NO;
        s_jam_shown = 0;
    });

    return UI_JAM_NONE;
}

/* Stubs for drive/tape status indicators (Phase 5: SwiftUI status bar) */
void ui_display_tape_counter(int port, int counter)          {}
void ui_display_tape_control_status(int port, int control)   {}
void ui_display_tape_motor_status(int port, int motor)       {}
void ui_display_volume(int vol)                              {}
void ui_display_joyport(uint16_t *joyport)                   {}
void ui_display_event_time(unsigned int current, unsigned int total) {}
void ui_display_playback(int playback_status, char *version) {}
void ui_display_recording(int recording_status)              {}
void ui_display_statustext(const char *text, bool fadeout)   {}
void ui_update_menus(void)                                   {}
void ui_set_tape_status(int port, int status)                {}
void ui_display_tape_current_image(int port, const char *image) {}
int  ui_extend_image_dialog(void)                  { return 0; }
void ui_display_paused(int flag, int warp_flag)    {}
char *ui_get_file(const char *fmt, ...)            { return NULL; }

/* ── vsyncapi.h implementation ──────────────────────────────────────────── */

/* vsyncarch_presync: runs on VICE thread before each frame.
 * Process NSEvents so keyboard/joystick input reaches the emulator.
 * mainlock_yield() lets the main thread acquire the lock if waiting.
 */
void vsyncarch_presync(void) {
    mainlock_yield();
    _kbd_drain();             /* drain buffered key events captured by NSEvent monitor */
    vice_mac_joystick_poll();
}

void vsyncarch_postsync(void) {
    /* Nothing required. Frame delivery happens in video_canvas_refresh(). */
}

/* vsyncarch_get_time: monotonic clock in microseconds */
unsigned long vsyncarch_get_time(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (unsigned long)(ts.tv_sec * 1000000UL + ts.tv_nsec / 1000UL);
}

void vsyncarch_sleep(unsigned long delay_us) {
    struct timespec ts = {
        .tv_sec  = (time_t)(delay_us / 1000000UL),
        .tv_nsec = (long)((delay_us % 1000000UL) * 1000UL),
    };
    nanosleep(&ts, NULL);
}

int vsyncarch_vbl_sync_enabled(void) {
    /* MTKView's displayLink drives timing; we don't rely on vsyncarch VBL. */
    return 0;
}

void vsyncarch_init(void) {}
void vsyncarch_display_speed(double speed, double frame_rate, int warp_enabled) {}

/* ── videoarch.h implementation ─────────────────────────────────────────── */

/* video arch init/shutdown — called by VICE core */
void video_arch_canvas_init(video_canvas_t *canvas) {
    canvas->initialized = 1;
}

int  video_arch_resources_init(void)          { return 0; }
void video_arch_resources_shutdown(void)      {}
int  video_arch_cmdline_options_init(void)    { return 0; }
char video_canvas_can_resize(video_canvas_t *canvas) { return 1; }
/* video_disabled_mode is defined in VICE's src/main.c (included in Phase 2 build) */
void video_shutdown(void)                     {}
int  video_arch_get_active_chip(void)         { return 0; }

/* video_canvas_t lifecycle */

static void vice_mac_alloc_argb_buffer(video_canvas_t *canvas,
                                       unsigned int width, unsigned int height) {
    lib_free(canvas->argb_buffer);
    canvas->argb_pitch  = width * 4;
    canvas->argb_buffer = (uint32_t *)lib_malloc(canvas->argb_pitch * height);
    memset(canvas->argb_buffer, 0, canvas->argb_pitch * height);
}

video_canvas_t *video_canvas_create(video_canvas_t *canvas,
                                    unsigned int *width, unsigned int *height,
                                    int mapped) {
    if (!canvas) return NULL;

    /* Accept whatever dimensions VICE requests; C64 is 384×272 with borders */
    canvas->width  = *width  ? *width  : VICE_MAC_CANVAS_W;
    canvas->height = *height ? *height : VICE_MAC_CANVAS_H;
    canvas->depth  = 32;  /* ARGB8888 — must match video_render_setphysicalcolor depth */

    vice_mac_alloc_argb_buffer(canvas, canvas->width, canvas->height);

    log_message(vice_mac_log, "video_canvas_create: %ux%u", canvas->width, canvas->height);
    return canvas;
}

void video_canvas_destroy(video_canvas_t *canvas) {
    if (!canvas) return;
    lib_free(canvas->argb_buffer);
    canvas->argb_buffer = NULL;
}

void video_canvas_resize(video_canvas_t *canvas, char resize_canvas) {
    if (!canvas || !canvas->draw_buffer) return;

    unsigned int w = canvas->draw_buffer->canvas_physical_width;
    unsigned int h = canvas->draw_buffer->canvas_physical_height;
    if (w == 0 || h == 0) return;

    if (canvas->width != w || canvas->height != h) {
        canvas->width  = w;
        canvas->height = h;
        vice_mac_alloc_argb_buffer(canvas, w, h);
        log_message(vice_mac_log, "video_canvas_resize: %ux%u", w, h);
    }
}

/* video_canvas_set_palette: initialise VICE's render color tables for ARGB8888 output.
 * Converts each palette entry to a packed 0xAARRGGBB 32-bit color and stores it in
 * the videoconfig color table so that video_render_main() can do the 8bpp→32bpp
 * conversion inline when rendering.
 */
int video_canvas_set_palette(video_canvas_t *canvas, struct palette_s *palette) {
    unsigned int i;
    video_render_color_tables_t *color_tables;

    if (!canvas || !palette) return 0;

    canvas->palette = palette;
    color_tables = &canvas->videoconfig->color_tables;

    for (i = 0; i < palette->num_entries; i++) {
        uint32_t col = (0xFFU                      << 24)
                     | ((uint32_t)palette->entries[i].red   << 16)
                     | ((uint32_t)palette->entries[i].green <<  8)
                     | ((uint32_t)palette->entries[i].blue);
        video_render_setphysicalcolor(canvas->videoconfig, (int)i, col, canvas->depth);
    }

    /* Raw RGB channel tables — used by some filter modes; build for 8-bit intensity. */
    for (i = 0; i < 256; i++) {
        video_render_setrawrgb(color_tables,
                               i,
                               (0xFFU << 24) | ((uint32_t)i << 16),  /* red channel   */
                               (0xFFU << 24) | ((uint32_t)i <<  8),  /* green channel */
                               (0xFFU << 24) | ((uint32_t)i));        /* blue channel  */
    }
    video_render_initraw(canvas->videoconfig);

    return 0;
}

/* video_canvas_refresh: called on VICE thread after each rendered frame.
 * Uses video_canvas_render() to convert palettized draw_buffer → ARGB8888,
 * then forwards the result to VICEDisplayManager for Metal upload.
 */
void video_canvas_refresh(video_canvas_t *canvas,
                          unsigned int xs, unsigned int ys,
                          unsigned int xi, unsigned int yi,
                          unsigned int w, unsigned int h) {
    if (!canvas || !canvas->draw_buffer || !canvas->argb_buffer) return;
    if (!canvas->videoconfig) return;

    /* Scale coordinates if the video config uses 2× or 3× integer scaling */
    xi *= canvas->videoconfig->scalex;
    w  *= canvas->videoconfig->scalex;
    yi *= canvas->videoconfig->scaley;
    h  *= canvas->videoconfig->scaley;

    /* Clamp to canvas bounds */
    if (xi + w > canvas->width)  w = canvas->width  - xi;
    if (yi + h > canvas->height) h = canvas->height - yi;
    if (w == 0 || h == 0) return;

    /* Convert palettized source → ARGB8888 render target */
    video_canvas_render(canvas,
                        (uint8_t *)canvas->argb_buffer,
                        (int)w, (int)h,
                        (int)xs, (int)ys,
                        (int)xi, (int)yi,
                        (int)canvas->argb_pitch);

    /* Forward the full ARGB8888 frame to the Metal display pipeline */
    Vice_DisplayManagerDidReceiveFrame(
        canvas->argb_buffer,
        (int)canvas->width,
        (int)canvas->height,
        (int)canvas->argb_pitch
    );
}

/* ── Platform lifecycle ─────────────────────────────────────────────────── */

int vice_mac_ui_init(void) {
    /* Create NSWindow and install VICEMetalView as its content view.
     * Called from VICE's main_program() → ui_init() during startup.
     * May be called from the main thread (via applicationDidFinishLaunching
     * → VICEEngine startWithMachine: → main_program). Use dispatch_sync as
     * a safety net for any future call-path that might differ. */

    dispatch_block_t createWindow = ^{
        /* 2× C64 native resolution as default window size */
        NSRect frame = NSMakeRect(0, 0, 768, 544);
        NSWindowStyleMask style =
            NSWindowStyleMaskTitled       |
            NSWindowStyleMaskClosable     |
            NSWindowStyleMaskMiniaturizable |
            NSWindowStyleMaskResizable;

        NSWindow *window = [[NSWindow alloc]
                             initWithContentRect:frame
                                       styleMask:style
                                         backing:NSBackingStoreBuffered
                                           defer:NO];
        window.title            = @"c=foundation";
        window.minSize          = NSMakeSize(384, 272);
        window.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;

        /* Create VICEMetalView sized to the C64 native frame */
        Vice_MetalViewCreate((__bridge void *)window,
                             VICE_MAC_CANVAS_W, VICE_MAC_CANVAS_H);

        /* Wire VICEDisplayManager → VICEMetalView */
        Vice_MetalViewSetDisplayManager();

        [window center];
        [window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        gEmulatorWindow = window;

        /* Register with status bridge so SwiftUIPanelCoordinator can
         * attach the status bar accessory view at startup. */
        [VICEStatusBridge sharedBridge].emulatorWindow = window;
    };

    if ([NSThread isMainThread]) {
        createWindow();
    } else {
        dispatch_sync(dispatch_get_main_queue(), createWindow);
    }

    return 0;
}

void vice_mac_ui_shutdown(void) {
    vice_mac_joystick_shutdown();
    dispatch_async(dispatch_get_main_queue(), ^{
        Vice_MetalViewDestroy();
    });
}

void vice_mac_process_pending_events(void) {
    /* No-op: event capture is now handled by the NSEvent local monitor
     * installed in ui_init_finalize.  Key events are buffered on the main
     * thread and drained in vsyncarch_presync via _kbd_drain(). */
}

void vice_mac_canvas_present(const uint32_t *pixels,
                              int width, int height, int rowPitch) {
    Vice_DisplayManagerDidReceiveFrame(pixels, width, height, rowPitch);
}

void vice_mac_ui_message(const char *text) {
    /* Informational messages go to stderr — too frequent for modal alerts. */
    fprintf(stderr, "[c=foundation] %s\n", text);
}

void vice_mac_ui_error(const char *text) {
    fprintf(stderr, "[c=foundation ERROR] %s\n", text);
    Vice_ShowError(text);
}

void vice_mac_ui_set_drive_led(unsigned int unit, unsigned int led,
                               unsigned int pwm) {
    (void)led;
    Vice_StatusSetDriveLED(unit, pwm);
}

void vice_mac_ui_set_drive_track(unsigned int unit, unsigned int track) {
    Vice_StatusSetDriveTrack(unit, track);
}

/* ── Stubs for symbols from excluded source files ───────────────────────── */
/* Note: main_program(), vice_thread_shutdown(), main_exit(), console_mode,
 * help_requested, default_settings_requested, video_disabled_mode are all
 * defined in VICE's src/main.c (included in Phase 2 build). */

/* main_exit — called by archdep_exit.c; terminate the app cleanly */
void main_exit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
}

/* ui_init_with_args — optional pre-init UI argument processing (Phase 5: pick up -model etc.) */
void ui_init_with_args(int *argc, char **argv) { (void)argc; (void)argv; }

/* video_init — video arch init hook called from main_program() before machine_init() */
int video_init(void) { return 0; }

/* PNG screenshot support — pngdrv.c excluded (requires libpng, Phase 5) */
void gfxoutput_init_png(int help) {}


/* Movie sound output — soundmovie.c excluded (Phase 5) */
int  sound_init_movie_device(void) { return 0; }
void soundmovie_start(void) {}
void soundmovie_stop(void) {}

/* WiC64 userport device — excluded (requires libcurl; Phase 7 handles networking) */
int  userport_wic64_resources_init(void)        { return 0; }
void userport_wic64_resources_shutdown(void)    {}
int  userport_wic64_cmdline_options_init(void)  { return 0; }

/* ── Arch stubs (Phase 5 / future phases) ───────────────────────────────── */

/* console_mode, help_requested, default_settings_requested, video_disabled_mode
 * are defined in vice/src/main.c which is compiled into libvice.dylib.
 * dlopen with RTLD_GLOBAL makes them available in the flat namespace. */

/* Variables defined in c128/c128cpu.c (not compiled for x64-only build) */
int maincpu_stretch = 0;
unsigned long c128cpu_memory_refresh_clk = 0;

/* fullscreen — not supported on macOS Metal path */
void fullscreen_capability(struct cap_fullscreen_s *cap_fullscreen) {}
void arch_ui_activate(void) {}

/* archdep thread lifecycle — archdep_exit.c only defines these for USE_GTK3UI */
void archdep_thread_init(void)     {}
void archdep_thread_shutdown(void) {}

/* UI actions/dispatch — Phase 5 */
void ui_dispatch_events(void) {}
void ui_display_reset(int device, int mode) {}
void ui_enable_drive_status(ui_drive_enable_t state, int *drive_led_color) {}
void ui_display_drive_current_image(unsigned int unit, unsigned int drive,
                                    const char *image) {}
void ui_resources_shutdown(void) {}

/* Canvas access — Phase 3 (Metal view); NULL is safe until then */
video_canvas_t *ui_get_active_canvas(void) { return NULL; }

/* ── Pause ──────────────────────────────────────────────────────────────── */

static volatile int is_paused = 0;

static void pause_loop(void *unused)
{
    /* Runs on the VICE thread (via vsync_on_vsync_do callback).
     * Yields the main lock every ~1/60 s so the UI stays responsive
     * while the emulator is frozen. */
    while (is_paused) {
        mainlock_yield_and_sleep(TICK_PER_SECOND / 60);
    }
}

int ui_pause_active(void) { return is_paused; }

void ui_pause_enable(void) {
    if (!is_paused) {
        is_paused = 1;
        vsync_on_vsync_do(pause_loop, NULL);
    }
}

void ui_pause_disable(void) {
    is_paused = 0;
}

bool ui_pause_loop_iteration(void) {
    if (!is_paused) return false;
    mainlock_yield_and_sleep(TICK_PER_SECOND / 60);
    return (bool)is_paused;
}

/* Joystick HID — Phase 5 (GameController framework) */
void joy_hidlib_init(void) {}
void joy_hidlib_exit(void) {}

/* Hotkeys arch translation — identity pass-through for now (Phase 5) */
uint32_t ui_hotkeys_arch_keysym_from_arch  (uint32_t arch_keysym)   { return arch_keysym; }
uint32_t ui_hotkeys_arch_keysym_to_arch    (uint32_t vice_keysym)   { return vice_keysym; }
uint32_t ui_hotkeys_arch_modifier_from_arch(uint32_t arch_mod)      { return arch_mod; }
uint32_t ui_hotkeys_arch_modifier_to_arch  (uint32_t vice_mod)      { return vice_mod; }
uint32_t ui_hotkeys_arch_modmask_from_arch (uint32_t arch_modmask)  { return arch_modmask; }
uint32_t ui_hotkeys_arch_modmask_to_arch   (uint32_t vice_modmask)  { return vice_modmask; }
void ui_hotkeys_arch_init(void) {}
void ui_hotkeys_arch_shutdown(void) {}
void ui_hotkeys_arch_install_by_map(ui_action_map_t *map) {}
void ui_hotkeys_arch_update_by_map(ui_action_map_t *map, uint32_t vice_keysym,
                                   uint32_t vice_modmask) {}
void ui_hotkeys_arch_remove_by_map(ui_action_map_t *map) {}
