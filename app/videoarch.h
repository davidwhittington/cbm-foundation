/*
 * videoarch.h — macOS arch video canvas definition for c=foundation.
 *
 * Replaces arch/sdl/videoarch.h and arch/headless/videoarch.h for our
 * native Metal rendering path. video_canvas_s holds all state the VICE
 * core needs; Metal-specific pointers live in the VICEDisplayManager
 * Objective-C layer and are not visible to pure-C core files.
 */

#ifndef VICE_VIDEOARCH_H
#define VICE_VIDEOARCH_H

#include <stdint.h>
#include "archdep.h"
#include "video.h"

#define VIDEO_CANVAS_IDX_VDC   1
#define VIDEO_CANVAS_IDX_VICII 0
#define MAX_CANVAS_NUM 2

struct video_canvas_s {
    /** \brief Nonzero if it is safe to access other members of the structure. */
    unsigned int initialized;

    /** \brief Nonzero if the structure has been fully realized. */
    unsigned int created;

    /** \brief Index of the canvas (used by x128 / xcbm2 for dual-screen). */
    int index;

    /** \brief Bit depth of the canvas (bits per pixel). */
    unsigned int depth;

    /** \brief Size of the drawable canvas area including black borders. */
    unsigned int width, height;

    /** \brief Size requested by the emulator core. */
    unsigned int real_width, real_height;

    /** \brief Actual window size (usually == width/height). */
    unsigned int actual_width, actual_height;

    /** \brief Rendering configuration as seen by the emulator core. */
    struct video_render_config_s *videoconfig;

    /** \brief CRT type index, tracks colour-encoding changes. */
    int crt_type;

    /** \brief Drawing buffer as seen by the emulator core. */
    struct draw_buffer_s *draw_buffer;

    /** \brief Secondary draw buffer used by the VSID player. */
    struct draw_buffer_s *draw_buffer_vsid;

    /** \brief Display window (viewport) as seen by the emulator core. */
    struct viewport_s *viewport;

    /** \brief Machine screen geometry as seen by the emulator core. */
    struct geometry_s *geometry;

    /** \brief Colour palette for translating display results. */
    struct palette_s *palette;

    /** \brief Back-pointer to the raster that owns this canvas. */
    struct raster_s *parent_raster;

    /** \brief Used to limit frame rate under warp. */
    tick_t warp_next_render_tick;

    /* ── macOS arch render target ───────────────────────────────────────── */

    /** \brief ARGB8888 render target — video_canvas_render() writes here. */
    uint32_t *argb_buffer;

    /** \brief Bytes per row in argb_buffer (= width * 4). */
    unsigned int argb_pitch;
};
typedef struct video_canvas_s video_canvas_t;

#endif /* VICE_VIDEOARCH_H */
