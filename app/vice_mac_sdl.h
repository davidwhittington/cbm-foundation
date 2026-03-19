/* vice_mac_sdl.h
 * macOS platform arch layer for c=foundation.
 * Replaces vice/src/arch/sdl/ entirely.
 *
 * This file is the direct analog of atari_mac_sdl.h from fuji-foundation.
 * It provides the C-callable interface between the VICE core callbacks
 * and the ObjC/Swift application layer.
 */

#ifndef VICE_MAC_SDL_H
#define VICE_MAC_SDL_H

#include <stdint.h>

/* ── Lifecycle ──────────────────────────────────────────────────────────── */

/**
 * Initialise the macOS platform layer.
 * Called from archdep_init() before any VICE subsystems start.
 * Sets up the NSApplication, installs the main window, creates the Metal view.
 */
int  vice_mac_ui_init(void);

/**
 * Shutdown the macOS platform layer.
 * Called from ui_shutdown().
 */
void vice_mac_ui_shutdown(void);

/* ── Event processing ───────────────────────────────────────────────────── */

/**
 * Process pending NSEvents (keyboard, mouse, joystick).
 * Called from vsyncarch_presync() on the VICE thread before each frame.
 * Dispatches input events to vice_mac_kbd.c and vice_mac_joy.c.
 */
void vice_mac_process_pending_events(void);

/* ── Display ────────────────────────────────────────────────────────────── */

/**
 * Called from video_canvas_refresh() after each rendered VICE frame.
 * Forwards the ARGB8888 frame buffer to VICEDisplayManager.
 *
 * @param pixels    ARGB8888 pixel data.
 * @param width     Frame width (typically 384 for C64).
 * @param height    Frame height (typically 272 for C64).
 * @param rowPitch  Bytes per row.
 */
void vice_mac_canvas_present(const uint32_t *pixels,
                              int width, int height, int rowPitch);

/* ── UI notifications (called from VICE core, posted to main thread) ────── */

/** Show a non-fatal message. Thread-safe; posts to main thread. */
void vice_mac_ui_message(const char *text);

/** Show an error. Thread-safe; posts to main thread. */
void vice_mac_ui_error(const char *text);

/** Update drive LED indicator for unit 8–11. */
void vice_mac_ui_set_drive_led(unsigned int unit, unsigned int led,
                               unsigned int pwm);

/** Update drive track indicator. */
void vice_mac_ui_set_drive_track(unsigned int unit, unsigned int track);

/* ── archdep overrides (called by VICE arch/shared layer) ──────────────── */

/**
 * Returns the path to the app bundle's Resources/vice-data/ directory.
 * Overrides archdep_get_vice_datadir() from arch/shared.
 * Caller must lib_free() the returned string.
 */
char *vice_mac_get_vice_datadir(void);

#endif /* VICE_MAC_SDL_H */
