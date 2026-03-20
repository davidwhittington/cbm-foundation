/* VICEEngine.m
 * ObjC implementation of the VICE bridge layer.
 * See VICEEngine.h for documentation.
 */

#import "VICEEngine.h"
#import "Net2IECManager.h"
#import "PhysDrvManager.h"
#import <dlfcn.h>

// VICE C headers
#include "main.h"
#include "machine.h"
#include "mainlock.h"
#include "attach.h"
#include "autostart.h"
#include "tape.h"
#include "cartridge.h"
#include "snapshot.h"
#include "resources.h"
#include "vsync.h"
#include "joystick.h"

@implementation VICEEngine {
    BOOL _running;
    BOOL _warpEnabled;
    BOOL _pauseEnabled;
    VICEMachineModel _currentMachine;
}

// MARK: - Singleton

+ (instancetype)sharedEngine {
    static VICEEngine *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[VICEEngine alloc] init]; });
    return instance;
}

+ (VICEMachineModel)compiledMachineClass {
    /* machine_class lives in libvice.dylib — resolve via dlsym so dyld doesn't
     * try to bind it at launch before the library is loaded. */
    int *mc = (int *)dlsym(RTLD_DEFAULT, "machine_class");
    if (!mc) return VICEMachineModelC64;
    switch (*mc) {
        case (1 << 0): return VICEMachineModelC64;
        case (1 << 8): return VICEMachineModelC64SC;
        default:       return VICEMachineModelC64;
    }
}

// MARK: - Library loading

+ (BOOL)loadVICELibrary:(NSError **)error {
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];

    NSString *appSupport = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    if (appSupport)
        [candidates addObject:[appSupport stringByAppendingPathComponent:@"cbm-foundation/libvice.dylib"]];

    NSString *bundled = [[NSBundle mainBundle] pathForResource:@"libvice" ofType:@"dylib"];
    if (bundled)
        [candidates addObject:bundled];

    for (NSString *path in candidates) {
        if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) continue;
        void *handle = dlopen(path.UTF8String, RTLD_LAZY | RTLD_GLOBAL);
        if (handle) return YES;
        NSLog(@"VICEEngine: dlopen failed for %@: %s", path, dlerror());
    }

    if (error) {
        *error = [NSError errorWithDomain:@"VICEEngineErrorDomain"
                                     code:-1
                                 userInfo:@{NSLocalizedDescriptionKey:
                                                @"VICE core library (libvice.dylib) not found. "
                                                @"Use the in-app setup to download it."}];
    }
    return NO;
}

// MARK: - Lifecycle

- (BOOL)startWithMachine:(VICEMachineModel)machine error:(NSError **)error {
    if (_running) {
        [self stop];
    }

    _currentMachine = machine;

    // Build a minimal argv. The machine class is determined at compile time
    // in Phase 1 (C64 only). Future phases will support multiple machine binaries.
    char *argv[] = { "cbmfoundation", NULL };
    int argc = 1;

    // main_program() initialises all VICE subsystems, then spawns the VICE
    // thread (because USE_VICE_THREAD is defined) and returns 0.
    int result = main_program(argc, argv);
    if (result != 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"VICEEngineErrorDomain"
                                         code:result
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"VICE initialisation failed"}];
        }
        return NO;
    }

    _running = YES;
    return YES;
}

- (void)stop {
    if (!_running) return;
    // vice_thread_shutdown() signals the VICE thread to exit and joins it.
    extern void vice_thread_shutdown(void);
    vice_thread_shutdown();
    machine_shutdown();
    _running = NO;
}

- (void)reset:(VICEResetMode)mode {
    if (!_running) return;
    mainlock_obtain();
    machine_trigger_reset(mode == VICEResetModeHard
                          ? MACHINE_RESET_MODE_POWER_CYCLE
                          : MACHINE_RESET_MODE_RESET_CPU);
    mainlock_release();
}

// MARK: - Running State

- (BOOL)isRunning    { return _running; }
- (VICEMachineModel)currentMachine { return _currentMachine; }

- (void)setWarpEnabled:(BOOL)warpEnabled {
    _warpEnabled = warpEnabled;
    if (_running) {
        mainlock_obtain();
        resources_set_int("WarpMode", warpEnabled ? 1 : 0);
        mainlock_release();
    }
}

- (BOOL)warpEnabled  { return _warpEnabled; }

- (void)setPauseEnabled:(BOOL)pauseEnabled {
    _pauseEnabled = pauseEnabled;
    if (_running) {
        extern void ui_pause_enable(void);
        extern void ui_pause_disable(void);
        if (pauseEnabled) {
            ui_pause_enable();
        } else {
            ui_pause_disable();
        }
    }
}

- (BOOL)pauseEnabled { return _pauseEnabled; }

// MARK: - Media

- (BOOL)attachDiskURL:(NSURL *)url unit:(NSInteger)unit drive:(NSInteger)drive
               error:(NSError **)error {
    mainlock_obtain();
    int result = file_system_attach_disk((unsigned int)unit,
                                         (unsigned int)drive,
                                         url.fileSystemRepresentation);
    mainlock_release();
    if (result < 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"VICEEngineErrorDomain"
                                         code:result
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"Failed to attach disk image"}];
        }
        return NO;
    }
    return YES;
}

- (void)detachDiskFromUnit:(NSInteger)unit drive:(NSInteger)drive {
    mainlock_obtain();
    file_system_detach_disk((unsigned int)unit, (unsigned int)drive);
    mainlock_release();
}

- (BOOL)attachTapeURL:(NSURL *)url error:(NSError **)error {
    mainlock_obtain();
    int result = tape_image_attach(1, url.fileSystemRepresentation);
    mainlock_release();
    if (result < 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"VICEEngineErrorDomain"
                                         code:result
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"Failed to attach tape image"}];
        }
        return NO;
    }
    return YES;
}

- (void)detachTape {
    mainlock_obtain();
    tape_image_detach(1);
    mainlock_release();
}

- (BOOL)attachCartridgeURL:(NSURL *)url error:(NSError **)error {
    mainlock_obtain();
    int result = cartridge_attach_image(CARTRIDGE_CRT, url.fileSystemRepresentation);
    mainlock_release();
    if (result < 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"VICEEngineErrorDomain"
                                         code:result
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"Failed to attach cartridge"}];
        }
        return NO;
    }
    return YES;
}

- (void)detachCartridge {
    mainlock_obtain();
    cartridge_detach_image(-1);
    mainlock_release();
}

// MARK: - Snapshots

- (BOOL)saveSnapshotToURL:(NSURL *)url error:(NSError **)error {
    mainlock_obtain();
    int result = machine_write_snapshot(url.fileSystemRepresentation, 1, 1, 0);
    mainlock_release();
    if (result < 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"VICEEngineErrorDomain"
                                         code:result
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"Failed to save snapshot"}];
        }
        return NO;
    }
    return YES;
}

- (BOOL)loadSnapshotFromURL:(NSURL *)url error:(NSError **)error {
    mainlock_obtain();
    int result = machine_read_snapshot(url.fileSystemRepresentation, 0);
    mainlock_release();
    if (result < 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"VICEEngineErrorDomain"
                                         code:result
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"Failed to load snapshot"}];
        }
        return NO;
    }
    return YES;
}

// MARK: - Input

- (void)keyDown:(uint16_t)macKeyCode modifiers:(NSUInteger)mods {
    extern void vice_mac_key_event(uint16_t keyCode, uint32_t mods, int down);
    vice_mac_key_event(macKeyCode, (uint32_t)mods, 1);
}

- (void)keyUp:(uint16_t)macKeyCode modifiers:(NSUInteger)mods {
    extern void vice_mac_key_event(uint16_t keyCode, uint32_t mods, int down);
    vice_mac_key_event(macKeyCode, (uint32_t)mods, 0);
}

- (void)joystickPort:(NSInteger)port direction:(uint8_t)dir fire:(BOOL)fire {
    if (!_running) return;
    uint8_t value = dir;
    if (fire) value |= 0x10;
    mainlock_obtain();
    joystick_set_value_absolute((unsigned int)port, value);
    mainlock_release();
}

// MARK: - Resources

- (void)setResourceInt:(NSString *)name value:(NSInteger)value {
    if (!_running) return;
    mainlock_obtain();
    resources_set_int(name.UTF8String, (int)value);
    mainlock_release();
}

- (void)setResourceString:(NSString *)name value:(NSString *)value {
    if (!_running) return;
    mainlock_obtain();
    resources_set_string(name.UTF8String, value.UTF8String);
    mainlock_release();
}

// MARK: - Net2IEC

- (void)connectNet2IECToHost:(NSString *)host
                        port:(NSInteger)port
                  completion:(void (^)(BOOL success, NSError *_Nullable error))completion
{
    [[Net2IECManager sharedManager] connectToHost:host
                                             port:(uint16_t)port
                                       completion:completion];
}

- (void)disconnectNet2IEC {
    [[Net2IECManager sharedManager] disconnect];
}

- (BOOL)isNet2IECConnected {
    return [Net2IECManager sharedManager].state == Net2IECStateConnected;
}

// MARK: - Physical Drive

- (BOOL)isPhysicalDriveAvailable {
    return [PhysDrvManager sharedManager].available;
}

- (BOOL)enablePhysicalDriveForUnit:(NSInteger)unit error:(NSError **)error {
    if (!_running) {
        if (error) {
            *error = [NSError errorWithDomain:@"VICEEngineErrorDomain"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"VICE is not running"}];
        }
        return NO;
    }
    return [[PhysDrvManager sharedManager] enableForUnit:unit error:error];
}

- (void)disablePhysicalDriveForUnit:(NSInteger)unit {
    [[PhysDrvManager sharedManager] disableForUnit:unit];
}

@end
