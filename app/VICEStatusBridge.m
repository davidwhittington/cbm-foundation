/* VICEStatusBridge.m
 * ObjC singleton bridge — routes VICE C callbacks to Swift status model.
 */

#import "VICEStatusBridge.h"
#import <dispatch/dispatch.h>

@implementation VICEStatusBridge

+ (instancetype)sharedBridge {
    static VICEStatusBridge *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[VICEStatusBridge alloc] init]; });
    return instance;
}

@end

/* ── C bridge functions ───────────────────────────────────────────────────── */

void Vice_StatusSetDriveLED(unsigned int unit, unsigned int pwm) {
    dispatch_async(dispatch_get_main_queue(), ^{
        VICEStatusBridge *b = [VICEStatusBridge sharedBridge];
        if (b.driveLEDHandler) {
            b.driveLEDHandler((NSInteger)unit, (NSInteger)pwm);
        }
    });
}

void Vice_StatusSetDriveTrack(unsigned int unit, unsigned int halfTrack) {
    dispatch_async(dispatch_get_main_queue(), ^{
        VICEStatusBridge *b = [VICEStatusBridge sharedBridge];
        if (b.driveTrackHandler) {
            b.driveTrackHandler((NSInteger)unit, (NSInteger)halfTrack);
        }
    });
}

void Vice_ShowError(const char *text) {
    NSString *msg = [NSString stringWithUTF8String:text ?: "Unknown error"];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert      = [[NSAlert alloc] init];
        alert.messageText   = @"c=foundation Error";
        alert.informativeText = msg;
        alert.alertStyle    = NSAlertStyleWarning;
        [alert runModal];
    });
}
