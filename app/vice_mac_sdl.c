/* vice_mac_sdl.c
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
 */

#include "vice_mac_sdl.h"
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

#include <stdbool.h>

#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <string.h>

/* C bridge to VICEDisplayManager (defined in VICEDisplayManager.m) */
extern void Vice_DisplayManagerDidReceiveFrame(const uint32_t *argbPixels,
                                               int width, int height, int rowPitch);

/* ── Static state ──────────────────────────────────────────────────────── */

static log_t vice_mac_log = LOG_DEFAULT;

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

/* JAM dialog — return CONTINUE for now (Phase 5: proper SwiftUI dialog) */
ui_jam_action_t ui_jam_dialog(const char *format, ...) {
    char buf[1024];
    va_list args;
    va_start(args, format);
    vsnprintf(buf, sizeof(buf), format, args);
    va_end(args);
    log_error(vice_mac_log, "CPU JAM: %s", buf);
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
    vice_mac_process_pending_events();
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
bool video_disabled_mode = false;
void video_shutdown(void)                     {}
int  video_arch_get_active_chip(void)         { return 0; }

/* video_canvas_t lifecycle */

video_canvas_t *video_canvas_create(video_canvas_t *canvas,
                                    unsigned int *width, unsigned int *height,
                                    int mapped) {
    if (!canvas) return NULL;

    /* Accept whatever dimensions VICE requests; C64 is 384x272 with borders */
    canvas->width  = *width  ? *width  : VICE_MAC_CANVAS_W;
    canvas->height = *height ? *height : VICE_MAC_CANVAS_H;
    canvas->depth  = 32;  /* ARGB8888 */

    log_message(vice_mac_log, "video_canvas_create: %ux%u", canvas->width, canvas->height);
    return canvas;
}

void video_canvas_destroy(video_canvas_t *canvas) {
    /* Nothing to free; MetalView lifetime is managed by AppKit */
}

void video_canvas_resize(video_canvas_t *canvas, char resize_canvas) {
    /* Phase 3: notify VICEMetalView of resolution change */
}

/* video_canvas_refresh: called on VICE thread after each rendered frame.
 * Forwards ARGB8888 buffer to VICEDisplayManager for Metal upload.
 */
void video_canvas_refresh(video_canvas_t *canvas,
                          unsigned int xs, unsigned int ys,
                          unsigned int xi, unsigned int yi,
                          unsigned int w, unsigned int h) {
    if (!canvas || !canvas->draw_buffer) return;

    /* Full-frame delivery: send the entire draw_buffer */
    Vice_DisplayManagerDidReceiveFrame(
        (const uint32_t *)canvas->draw_buffer,
        (int)canvas->width,
        (int)canvas->height,
        (int)(canvas->width * 4)  /* rowPitch = width * 4 bytes */
    );
}

int video_canvas_set_palette(video_canvas_t *canvas, struct palette_s *palette) {
    /* Phase 3: translate VICE palette to Metal-friendly format if needed */
    return 0;
}

/* ── Platform lifecycle ─────────────────────────────────────────────────── */

/* C bridges into ObjC layer (defined in VICEMetalView.m and VICEDisplayManager.m) */
extern void Vice_MetalViewCreate(void *nsWindow, int width, int height);
extern void Vice_MetalViewSetDisplayManager(void);

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
    };

    if ([NSThread isMainThread]) {
        createWindow();
    } else {
        dispatch_sync(dispatch_get_main_queue(), createWindow);
    }

    return 0;
}

void vice_mac_ui_shutdown(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        /* Release Metal view on main thread */
        Vice_MetalViewDestroy();
    });
}

void vice_mac_process_pending_events(void) {
    /* Drain the NSEvent queue so keyboard and joystick events reach VICE.
     * Called from vsyncarch_presync() on the VICE thread before each frame.
     * NSEvent processing must happen on the main thread; use dispatch_sync
     * so the VICE thread waits until the batch is drained. */
    dispatch_sync(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            NSEvent *event;
            while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                              untilDate:nil
                                                 inMode:NSDefaultRunLoopMode
                                                dequeue:YES]) != nil) {
                switch (event.type) {
                    case NSEventTypeKeyDown:
                        vice_mac_key_event((uint16_t)event.keyCode,
                                          (uint32_t)event.modifierFlags,
                                          1);
                        break;
                    case NSEventTypeKeyUp:
                        vice_mac_key_event((uint16_t)event.keyCode,
                                          (uint32_t)event.modifierFlags,
                                          0);
                        break;
                    default:
                        [NSApp sendEvent:event];
                        break;
                }
            }
        }
    });
}

void vice_mac_canvas_present(const uint32_t *pixels,
                              int width, int height, int rowPitch) {
    Vice_DisplayManagerDidReceiveFrame(pixels, width, height, rowPitch);
}

void vice_mac_ui_message(const char *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        /* Phase 5: show NSAlert or post to SwiftUI status */
        fprintf(stderr, "[c=foundation] %s\n", text);
    });
}

void vice_mac_ui_error(const char *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        fprintf(stderr, "[c=foundation ERROR] %s\n", text);
    });
}

void vice_mac_ui_set_drive_led(unsigned int unit, unsigned int led,
                               unsigned int pwm) {
    /* Phase 5: update SwiftUI drive status indicator */
}

void vice_mac_ui_set_drive_track(unsigned int unit, unsigned int track) {
    /* Phase 5: update SwiftUI drive track display */
}

/* ── Stubs for symbols from excluded source files ───────────────────────── */
/* Note: main_program(), vice_thread_shutdown(), main_exit(), console_mode,
 * help_requested, default_settings_requested, video_disabled_mode are all
 * defined in VICE's src/main.c which is now included in the build. */

/* PNG screenshot support — pngdrv.c excluded (requires libpng, Phase 5) */
void gfxoutput_init_png(int help) {}

/* Printer graphics output — output-graphics.c excluded (Phase 5) */
void output_graphics_init(void) {}
int  output_graphics_init_resources(void) { return 0; }
void output_graphics_shutdown(void) {}

/* Movie sound output — soundmovie.c excluded (Phase 5) */
int  sound_init_movie_device(void) { return 0; }
void soundmovie_start(void) {}
void soundmovie_stop(void) {}

/* WiC64 userport device — excluded (requires libcurl; Phase 7 handles networking) */
int  userport_wic64_resources_init(void)        { return 0; }
void userport_wic64_resources_shutdown(void)    {}
int  userport_wic64_cmdline_options_init(void)  { return 0; }

/* ── Arch stubs (Phase 5 / future phases) ───────────────────────────────── */

/* Global state variables normally defined in main.c are now provided by VICE's
 * src/main.c (included in Phase 2 build): console_mode, help_requested,
 * default_settings_requested, video_disabled_mode. */

/* Variables defined in c128/c128cpu.c (not compiled for x64-only Phase 1-5) */
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

/* Pause — Phase 5 */
int  ui_pause_active(void)          { return 0; }
void ui_pause_enable(void)          {}
void ui_pause_disable(void)         {}
bool ui_pause_loop_iteration(void)  { return false; }

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
