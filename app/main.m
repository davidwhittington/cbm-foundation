/* main.m — c=foundation ObjC entry point
 * Phase 2: delegates to NSApplicationMain so AppKit owns the run loop.
 * The VICE engine is started by AppDelegate after the application launches.
 */

#import <AppKit/AppKit.h>
#import "AppDelegate.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
