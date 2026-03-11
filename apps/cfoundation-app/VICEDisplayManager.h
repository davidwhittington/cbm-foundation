/* VICEDisplayManager.h
 * Lock-free frame pipeline between the VICE emulator thread and the Metal render thread.
 * Mirrors the display manager pattern from fuji-foundation.
 *
 * Called from vice_mac_sdl.c::video_canvas_refresh() on the VICE thread.
 * Forwards frames to VICEMetalView on the main thread via atomic pointer swap.
 */

#pragma once

#ifdef __OBJC__
#import <Foundation/Foundation.h>
@class VICEMetalView;

@interface VICEDisplayManager : NSObject

/** The Metal view that receives frames. Set once at startup. */
@property (nonatomic, weak, nullable) VICEMetalView *metalView;

/** Shared singleton. */
+ (instancetype _Nonnull)sharedManager;

/**
 * Deliver a new VICE frame.
 * Safe to call from any thread. Uses double-buffering to avoid blocking the VICE thread.
 *
 * @param argbPixels  ARGB8888 pixel data from video_canvas_refresh().
 * @param width       Frame width in pixels.
 * @param height      Frame height in pixels.
 * @param rowPitch    Bytes per row.
 */
- (void)didReceiveFrame:(const uint32_t * _Nonnull)argbPixels
                  width:(NSInteger)width
                 height:(NSInteger)height
               rowPitch:(NSInteger)rowPitch;

@end
#endif /* __OBJC__ */

/* C-callable bridge for vice_mac_sdl.c */
#ifdef __cplusplus
extern "C" {
#endif

void Vice_DisplayManagerDidReceiveFrame(const uint32_t *argbPixels,
                                        int width, int height, int rowPitch);

#ifdef __cplusplus
}
#endif
