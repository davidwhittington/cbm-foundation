/* vice_mac_sdl.c
 * macOS platform arch layer for c=foundation.
 * Implements VICE's uiapi.h, vsyncapi.h, and videoarch.h contracts.
 *
 * This is the central arch file, analogous to atari_mac_sdl.c in fuji-foundation.
 * It replaces everything under vice/src/arch/sdl/.
 *
 * Phase 2 implementation: stubs that compile and link.
 * Metal presentation and event processing are wired in Phase 3.
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
    if (!resURL) return lib_stralloc("/usr/local/share/vice");

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
void ui_display_tape_counter(int counter)          {}
void ui_display_tape_control_status(int motor)     {}
void ui_display_tape_motor_status(int motor)       {}
void ui_display_volume(int vol)                    {}
void ui_display_joyport(uint16_t *joyport)         {}
void ui_display_event_time(unsigned int current, unsigned int total) {}
void ui_display_playback(int playback_status, char *version) {}
void ui_display_recording(int recording_status)    {}
void ui_display_statustext(const char *text, int fade_out) {}
void ui_update_menus(void)                         {}
void ui_set_tape_status(int port, int status)      {}
void ui_display_tape_current_image(const char *image) {}
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

void video_canvas_set_palette(video_canvas_t *canvas, struct palette_s *palette) {
    /* Phase 3: translate VICE palette to Metal-friendly format if needed */
}

/* ── Platform lifecycle ─────────────────────────────────────────────────── */

int vice_mac_ui_init(void) {
    /* Phase 2: create NSWindow and install VICEMetalView.
     * Full implementation in Phase 3 when Metal view is ready. */
    return 0;
}

void vice_mac_ui_shutdown(void) {
    /* Phase 2: teardown. */
}

void vice_mac_process_pending_events(void) {
    /* Phase 2: drain NSEvent queue for keyboard/joystick.
     * Implemented in vice_mac_kbd.c and vice_mac_joy.c. */
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
