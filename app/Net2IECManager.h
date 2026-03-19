/* Net2IECManager.h
 * ObjC TCP connection manager for the net2iec IEC-over-TCP bridge.
 */
#pragma once
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, Net2IECState) {
    Net2IECStateDisconnected = 0,
    Net2IECStateConnecting,
    Net2IECStateConnected,
    Net2IECStateError,
};

@interface Net2IECManager : NSObject

@property (class, readonly) Net2IECManager *sharedManager;
@property (nonatomic, readonly) Net2IECState state;
@property (nonatomic, copy, nullable) NSString *lastError;

/** Connect to Meatloaf/FujiNet-PC at host:port. Async; completion on main queue. */
- (void)connectToHost:(NSString *)host
                 port:(uint16_t)port
           completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

/** Disconnect and detach from VICE IEC bus. */
- (void)disconnect;

@end
