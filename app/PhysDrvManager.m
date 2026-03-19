/* PhysDrvManager.m
 * ObjC implementation of the physical drive manager.
 */

#import "PhysDrvManager.h"

// VICE C headers
#include "serial.h"
#include "realdevice.h"
#include "mainlock.h"

// Declared in opencbmlib.c (compiled under HAVE_REALDEVICE)
extern unsigned int opencbmlib_is_available(void);

// Declared in serial/serial-realdevice.c
extern int  serial_realdevice_enable(void);
extern void serial_realdevice_disable(void);

// Declared in serial/serial-device.c
extern void serial_device_type_set(unsigned int type, unsigned int unit);

@implementation PhysDrvManager {
    BOOL      _setupDone;
    NSInteger _enabledUnit;   // IEC unit currently routed to real hw, or -1
}

+ (instancetype)sharedManager {
    static PhysDrvManager *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[PhysDrvManager alloc] init]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _state       = PhysDrvStateUnavailable;
        _enabledUnit = -1;
    }
    return self;
}

- (void)setup {
    if (_setupDone) return;
    _setupDone = YES;

    // realdevice_init() calls opencbmlib_open() which dlopens libopencbm.dylib.
    // Safe before VICE starts — no mainlock needed here.
    realdevice_init();

    _state = opencbmlib_is_available() ? PhysDrvStateDisabled
                                       : PhysDrvStateUnavailable;
}

- (BOOL)isAvailable {
    return _state != PhysDrvStateUnavailable;
}

- (BOOL)enableForUnit:(NSInteger)unit error:(NSError **)error {
    if (_state == PhysDrvStateEnabled) {
        // Already enabled on another unit — disable first.
        [self disableForUnit:_enabledUnit];
    }

    mainlock_obtain();
    int result = serial_realdevice_enable();
    if (result == 0) {
        serial_device_type_set(SERIAL_DEVICE_REAL, (unsigned int)unit);
    }
    mainlock_release();

    if (result != 0) {
        _state     = PhysDrvStateError;
        _lastError = @"Cannot open opencbm driver. Is a ZoomFloppy or XUM1541 connected?";
        if (error) {
            *error = [NSError errorWithDomain:@"PhysDrvErrorDomain"
                                         code:result
                                     userInfo:@{NSLocalizedDescriptionKey: _lastError}];
        }
        return NO;
    }

    _enabledUnit = unit;
    _state       = PhysDrvStateEnabled;
    _lastError   = nil;
    return YES;
}

- (void)disableForUnit:(NSInteger)unit {
    if (_state != PhysDrvStateEnabled) return;

    mainlock_obtain();
    serial_device_type_set(SERIAL_DEVICE_FS, (unsigned int)unit);
    serial_realdevice_disable();
    mainlock_release();

    _enabledUnit = -1;
    _state       = PhysDrvStateDisabled;
}

@end
