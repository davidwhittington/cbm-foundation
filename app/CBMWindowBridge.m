#import "CBMWindowBridge.h"

// Forward-declare the Metal view global from VICEMetalView.m
extern NSView *_Nullable Vice_GetMetalView(void);

// Observers receive this when VICE is ready
NSNotificationName const CBMVICEReadyNotification = @"CBMVICEReadyNotification";

@implementation CBMWindowBridge

+ (NSView *_Nullable)sharedMetalView {
    return Vice_GetMetalView();
}

+ (void)notifyVICEReady {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:CBMVICEReadyNotification object:nil];
    });
}

@end
