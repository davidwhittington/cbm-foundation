/* VICEMetalView.h
 * MTKView subclass and Metal rendering pipeline for c=foundation.
 * Mirrors EmulatorMetalView.h from fuji-foundation.
 *
 * C64 native frame size: 384 x 272 (full frame with borders).
 * Input: ARGB8888 32-bit pixel buffer from VICE video_canvas_refresh().
 */

#pragma once

#ifdef __OBJC__
#import <MetalKit/MetalKit.h>

@interface VICEMetalView : MTKView <MTKViewDelegate>

/** C64 output resolution. Defaults to 384x272. */
@property (nonatomic) CGSize emulatorResolution;

/** Enable scanline darkening (every other row dimmed). Default NO. */
@property (nonatomic) BOOL scanlinesEnabled;

/** Scanline brightness multiplier (0.0 = fully dark, 1.0 = off). Default 0.72. */
@property (nonatomic) float scanlineTransparency;

/** Enable CRT barrel distortion. Default NO. */
@property (nonatomic) BOOL crtCurvatureEnabled;

/** Enable bilinear texture filtering. Default NO (nearest-neighbour). */
@property (nonatomic) BOOL linearFilterEnabled;

/** Display brightness (0.0–2.0). Default 1.0. */
@property (nonatomic) float brightness;

/** Color saturation (0.0 = greyscale, 1.0 = normal, 2.0 = oversaturated). Default 1.0. */
@property (nonatomic) float saturation;

/** Contrast (0.0–2.0). Default 1.0. */
@property (nonatomic) float contrast;

/**
 * Upload a new VICE frame and render it immediately (synchronous on Metal thread).
 *
 * @param pixels      ARGB8888 pixel data, width × height.
 * @param width       Width of the VICE frame in pixels (typically 384 for C64).
 * @param height      Height of the VICE frame in pixels (typically 272 for C64).
 * @param rowPitch    Bytes per source row (may be > width*4 if stride-padded).
 */
- (void)presentFrame:(const uint32_t *)pixels
               width:(NSInteger)width
              height:(NSInteger)height
            rowPitch:(NSInteger)rowPitch;

@end
#endif /* __OBJC__ */

/* C-callable bridge — allows vice_mac_sdl.c (plain C) to call the Metal view */

#ifdef __cplusplus
extern "C" {
#endif

/** Create the VICEMetalView and install it as the NSWindow content view. */
void Vice_MetalViewCreate(void *nsWindow, int width, int height);

/** Upload a new frame. Called from video_canvas_refresh() on the VICE thread. */
void Vice_MetalPresent(const uint32_t *argbPixels,
                       int width, int height, int rowPitch);

/** Enable/disable scanlines (1 = on, 0 = off). */
void Vice_MetalSetScanlines(int enabled);

/** Set scanline transparency (0.0 = fully dark, 1.0 = fully bright). */
void Vice_MetalSetScanlineTransparency(double transparency);

/** Enable/disable bilinear filtering. */
void Vice_MetalSetLinearFilter(int enabled);

/** Destroy the view on app shutdown. */
void Vice_MetalViewDestroy(void);

#ifdef __cplusplus
}
#endif
