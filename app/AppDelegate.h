/* AppDelegate.h
 * NSApplicationDelegate for c=foundation.
 * Owns the VICE engine lifecycle: starts on launch, stops on quit.
 */

#pragma once
#import <AppKit/AppKit.h>

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>

@property (nonatomic, copy, nullable) void (^setupCompletion)(void);
@property (nonatomic, strong, nullable) NSWindow *setupWindow;

@end
