/* VICEDisplayManager.m
 * Lock-free frame pipeline between the VICE emulator thread and the Metal render thread.
 * Ported from fuji-foundation's display manager pattern.
 */

#import "VICEDisplayManager.h"
#import "VICEMetalView.h"
#import <os/lock.h>
#import <stdlib.h>
#import <string.h>

@implementation VICEDisplayManager {
    // Double-buffer pointers
    uint32_t *_bufA;
    uint32_t *_bufB;
    NSInteger _bufWidth;
    NSInteger _bufHeight;
    NSInteger _bufRowPitch;
    size_t    _bufBytes;
    BOOL      _aIsFront;  // YES = _bufA is front (being read), _bufB is back (being written)
    os_unfair_lock _lock;
}

+ (instancetype)sharedManager {
    static VICEDisplayManager *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[VICEDisplayManager alloc] init]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lock    = OS_UNFAIR_LOCK_INIT;
        _aIsFront = YES;
    }
    return self;
}

- (void)dealloc {
    free(_bufA);
    free(_bufB);
}

- (void)_ensureBufferCapacityWidth:(NSInteger)w height:(NSInteger)h rowPitch:(NSInteger)rp {
    size_t needed = (size_t)(rp * h);
    if (needed <= _bufBytes &&
        _bufWidth == w && _bufHeight == h) return;

    free(_bufA); free(_bufB);
    _bufA     = malloc(needed);
    _bufB     = malloc(needed);
    _bufBytes = needed;
    _bufWidth  = w;
    _bufHeight = h;
    _bufRowPitch = rp;
}

- (void)didReceiveFrame:(const uint32_t *)argbPixels
                  width:(NSInteger)width
                 height:(NSInteger)height
               rowPitch:(NSInteger)rowPitch {
    os_unfair_lock_lock(&_lock);
    [self _ensureBufferCapacityWidth:width height:height rowPitch:rowPitch];

    // Write into whichever buffer is currently the back buffer
    uint32_t *back = _aIsFront ? _bufB : _bufA;
    memcpy(back, argbPixels, (size_t)(rowPitch * height));

    // Swap front/back
    _aIsFront = !_aIsFront;
    os_unfair_lock_unlock(&_lock);

    // Forward to Metal view — which does its own swap on the render thread
    [_metalView presentFrame:(_aIsFront ? _bufA : _bufB)
                       width:width
                      height:height
                    rowPitch:rowPitch];
}

@end

// MARK: - C bridge

void Vice_DisplayManagerDidReceiveFrame(const uint32_t *argbPixels,
                                        int width, int height, int rowPitch) {
    [[VICEDisplayManager sharedManager] didReceiveFrame:argbPixels
                                                  width:width
                                                 height:height
                                               rowPitch:rowPitch];
}
