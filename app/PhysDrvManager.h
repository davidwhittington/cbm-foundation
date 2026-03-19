/* PhysDrvManager.h
 * ObjC wrapper for VICE's opencbm/realdevice physical drive subsystem.
 * Enables real 1541/1571/1581 access via ZoomFloppy or XUM1541 adapters.
 *
 * Build-time: uses VICE's bundled src/lib/opencbm.h — no Homebrew install needed.
 * Runtime:    requires libopencbm.dylib (brew install opencbm) and a USB adapter.
 *             Degrades gracefully when the dylib is absent.
 */

#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PhysDrvState) {
    PhysDrvStateUnavailable = 0, ///< libopencbm.dylib not found at runtime
    PhysDrvStateDisabled,        ///< dylib loaded, driver not yet opened
    PhysDrvStateEnabled,         ///< driver open, unit routed to real hardware
    PhysDrvStateError,           ///< last enable() call failed
} NS_SWIFT_NAME(PhysicalDriveState);

NS_SWIFT_NAME(PhysDrvManager)
@interface PhysDrvManager : NSObject

@property (class, readonly) PhysDrvManager *sharedManager;

/** Current state of the physical drive subsystem. */
@property (nonatomic, readonly) PhysDrvState state;

/** Error message from the most recent failed enable call. */
@property (nonatomic, copy, nullable) NSString *lastError;

/**
 * Probe for libopencbm.dylib availability.
 * Safe to call before VICE starts — does not require a running emulator.
 * Call once at app startup (e.g. from AppDelegate).
 */
- (void)setup;

/** YES if libopencbm.dylib loaded successfully. */
@property (nonatomic, readonly, getter=isAvailable) BOOL available;

/**
 * Enable physical drive passthrough on IEC unit 8–11.
 * Opens the XUM1541/ZoomFloppy kernel driver and routes the given unit
 * to real hardware.  Must be called while VICE is running.
 */
- (BOOL)enableForUnit:(NSInteger)unit error:(NSError *_Nullable *_Nullable)error;

/**
 * Disable physical drive passthrough and restore virtual emulation for
 * the given unit.
 */
- (void)disableForUnit:(NSInteger)unit;

@end

NS_ASSUME_NONNULL_END
