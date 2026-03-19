/* VICEStatusBridge.h
 * C-to-Swift bridge for drive status indicators and alert dialogs.
 *
 * Drive LED/track updates arrive on the VICE emulation thread; this bridge
 * dispatches them to the main thread and invokes registered Swift callbacks.
 *
 * The emulator NSWindow is stored here so SwiftUIPanelCoordinator can
 * attach the status bar accessory view after VICE starts.
 */

#pragma once

#ifdef __OBJC__
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface VICEStatusBridge : NSObject

+ (instancetype)sharedBridge NS_SWIFT_NAME(shared());

/** The emulator NSWindow. Set by vice_mac_ui_init() after window creation. */
@property (nonatomic, weak, nullable) NSWindow *emulatorWindow;

/**
 * Called on the main thread when a drive LED changes.
 * unit: 0–3 (maps to IEC units 8–11).  pwm: 0 = off, >0 = on (0–255).
 */
@property (copy, nullable) void (^driveLEDHandler)(NSInteger unit, NSInteger pwm);

/**
 * Called on the main thread when a drive track position changes.
 * unit: 0–3.  halfTrack: current half-track number (divide by 2 for track).
 */
@property (copy, nullable) void (^driveTrackHandler)(NSInteger unit, NSInteger halfTrack);

@end

NS_ASSUME_NONNULL_END
#endif /* __OBJC__ */

/* C-callable functions — safe to call from any thread. */
#ifdef __cplusplus
extern "C" {
#endif

/** Notify the status bar that a drive LED changed (called on VICE thread). */
void Vice_StatusSetDriveLED(unsigned int unit, unsigned int pwm);

/** Notify the status bar that a drive track position changed (called on VICE thread). */
void Vice_StatusSetDriveTrack(unsigned int unit, unsigned int halfTrack);

/** Show an error alert on the main thread (non-blocking for caller). */
void Vice_ShowError(const char *text);

#ifdef __cplusplus
}
#endif
