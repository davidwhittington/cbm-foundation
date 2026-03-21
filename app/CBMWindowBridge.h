#pragma once
#import <AppKit/AppKit.h>

/// Thin ObjC bridge exposing the VICE Metal view and engine state to Swift.
@interface CBMWindowBridge : NSObject

/// Returns gMetalView (set by Vice_MetalViewCreate) or nil before VICE inits.
+ (NSView *_Nullable)sharedMetalView;

/// Notify the SwiftUI layer that VICE has started and the Metal view is ready.
+ (void)notifyVICEReady;

@end
