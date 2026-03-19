/* VICEEngine.h
 * ObjC bridge between the Swift/AppKit GUI layer and the VICE C emulation core.
 * Mirrors Atari800Engine.h from fuji-foundation.
 *
 * All calls into VICE C APIs are made through this class.
 * Internally acquires mainlock before calling any VICE C function.
 */

#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, VICEMachineModel) {
    VICEMachineModelC64   = 0,  // C64 with 6567/6569 VIC-II
    VICEMachineModelC64SC = 1,  // Cycle-exact C64 (x64sc)
    VICEMachineModelC128  = 2,
    VICEMachineModelVIC20 = 3,
    VICEMachineModelPET   = 4,
    VICEMachineModelPlus4 = 5,
} NS_SWIFT_NAME(MachineModel);

typedef NS_ENUM(NSInteger, VICEResetMode) {
    VICEResetModeSoft  = 0,
    VICEResetModeHard  = 1,
} NS_SWIFT_NAME(ResetMode);

NS_SWIFT_NAME(VICEEngine)
@interface VICEEngine : NSObject

+ (instancetype)sharedEngine NS_SWIFT_NAME(shared());

/** The machine class this binary was compiled for (read from VICE's machine_class global). */
+ (VICEMachineModel)compiledMachineClass NS_SWIFT_NAME(compiledMachineClass());

// MARK: - Lifecycle

/** Start the VICE emulator for the given machine. Spawns the VICE thread. */
- (BOOL)startWithMachine:(VICEMachineModel)machine
                   error:(NSError *_Nullable *_Nullable)error;

/** Shutdown VICE thread and free all resources. */
- (void)stop;

/** Trigger a soft or hard reset. */
- (void)reset:(VICEResetMode)mode;

// MARK: - Running State

@property (nonatomic, readonly, getter=isRunning) BOOL running;
@property (nonatomic) BOOL warpEnabled;
@property (nonatomic) BOOL pauseEnabled;
@property (nonatomic, readonly) VICEMachineModel currentMachine;

// MARK: - Media

/** Attach a disk image to the given unit (8-11) and drive (0-1). */
- (BOOL)attachDiskURL:(NSURL *)url
                 unit:(NSInteger)unit
                drive:(NSInteger)drive
                error:(NSError *_Nullable *_Nullable)error;

- (void)detachDiskFromUnit:(NSInteger)unit drive:(NSInteger)drive;

- (BOOL)attachTapeURL:(NSURL *)url
                error:(NSError *_Nullable *_Nullable)error;
- (void)detachTape;

- (BOOL)attachCartridgeURL:(NSURL *)url
                     error:(NSError *_Nullable *_Nullable)error;
- (void)detachCartridge;

// MARK: - Snapshots

- (BOOL)saveSnapshotToURL:(NSURL *)url error:(NSError *_Nullable *_Nullable)error;
- (BOOL)loadSnapshotFromURL:(NSURL *)url error:(NSError *_Nullable *_Nullable)error;

// MARK: - Input

/** Deliver a key event to the C64 keyboard matrix. Call from main thread. */
- (void)keyDown:(uint16_t)macKeyCode modifiers:(NSUInteger)mods;
- (void)keyUp:(uint16_t)macKeyCode modifiers:(NSUInteger)mods;

/** Update joystick state for the given port (1 or 2). */
- (void)joystickPort:(NSInteger)port direction:(uint8_t)dir fire:(BOOL)fire;

// MARK: - Resources

/** Set a VICE integer resource. Acquires mainlock. */
- (void)setResourceInt:(NSString *)name value:(NSInteger)value;

/** Set a VICE string resource. Acquires mainlock. */
- (void)setResourceString:(NSString *)name value:(NSString *)value;

// MARK: - Net2IEC

/** Connect net2iec to a Meatloaf/FujiNet-PC server. Completion on main queue. */
- (void)connectNet2IECToHost:(NSString *)host
                        port:(NSInteger)port
                  completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

/** Disconnect net2iec. */
- (void)disconnectNet2IEC;

/** Returns YES if net2iec is currently connected. */
@property (nonatomic, readonly, getter=isNet2IECConnected) BOOL net2IECConnected;

// MARK: - Physical Drive (opencbm / ZoomFloppy / XUM1541)

/** YES if libopencbm.dylib loaded successfully at startup. */
@property (nonatomic, readonly, getter=isPhysicalDriveAvailable) BOOL physicalDriveAvailable;

/** Enable physical drive passthrough for IEC unit 8–11. */
- (BOOL)enablePhysicalDriveForUnit:(NSInteger)unit
                             error:(NSError *_Nullable *_Nullable)error;

/** Disable physical drive passthrough and restore virtual emulation for the unit. */
- (void)disablePhysicalDriveForUnit:(NSInteger)unit;

@end

NS_ASSUME_NONNULL_END
