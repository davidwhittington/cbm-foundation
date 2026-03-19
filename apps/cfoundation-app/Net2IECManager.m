/* Net2IECManager.m
 * ObjC TCP connection manager for the net2iec IEC-over-TCP bridge.
 * Manages the POSIX socket lifecycle on behalf of VICE.
 */

#import "Net2IECManager.h"
#include "vice_net2iec.h"

#include <sys/socket.h>
#include <netdb.h>
#include <fcntl.h>
#include <sys/select.h>
#include <sys/time.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

@implementation Net2IECManager {
    Net2IECState _state;
    NSString    *_lastError;
    int          _sock;
    dispatch_queue_t _connectQueue;
}

// MARK: - Singleton

+ (Net2IECManager *)sharedManager {
    static Net2IECManager *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[Net2IECManager alloc] init]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _state = Net2IECStateDisconnected;
        _sock  = -1;
        _connectQueue = dispatch_queue_create("com.cfoundation.net2iec.connect",
                                              DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

// MARK: - Properties

- (Net2IECState)state     { return _state; }
- (NSString *)lastError   { return _lastError; }
- (void)setLastError:(NSString *)lastError { _lastError = [lastError copy]; }

// MARK: - Connect

- (void)connectToHost:(NSString *)host
                 port:(uint16_t)port
           completion:(void (^)(BOOL, NSError *_Nullable))completion
{
    dispatch_async(_connectQueue, ^{
        [self _connectToHost:host port:port completion:completion];
    });
}

- (void)_connectToHost:(NSString *)host
                  port:(uint16_t)port
            completion:(void (^)(BOOL, NSError *_Nullable))completion
{
    /* Disconnect any existing connection first */
    [self _closeSocket];

    dispatch_async(dispatch_get_main_queue(), ^{
        self->_state = Net2IECStateConnecting;
    });

    /* Resolve host */
    char portStr[8];
    snprintf(portStr, sizeof(portStr), "%u", (unsigned)port);

    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family   = AF_INET;
    hints.ai_socktype = SOCK_STREAM;

    struct addrinfo *res = NULL;
    int gai_err = getaddrinfo(host.UTF8String, portStr, &hints, &res);
    if (gai_err != 0 || res == NULL) {
        NSString *errMsg = [NSString stringWithFormat:@"Host resolution failed: %s",
                            gai_strerror(gai_err)];
        [self _failWithMessage:errMsg completion:completion];
        return;
    }

    /* Create socket */
    int fd = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (fd < 0) {
        freeaddrinfo(res);
        [self _failWithMessage:@"socket() failed" completion:completion];
        return;
    }

    /* Set non-blocking for connect with timeout */
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    int rc = connect(fd, res->ai_addr, res->ai_addrlen);
    freeaddrinfo(res);

    if (rc < 0 && errno != EINPROGRESS) {
        close(fd);
        [self _failWithMessage:[NSString stringWithFormat:@"connect() failed: %s",
                                strerror(errno)]
                    completion:completion];
        return;
    }

    /* Wait for connect to complete with 5-second timeout */
    if (rc != 0) {
        fd_set wfds;
        FD_ZERO(&wfds);
        FD_SET(fd, &wfds);
        struct timeval tv = { .tv_sec = 5, .tv_usec = 0 };
        int sel = select(fd + 1, NULL, &wfds, NULL, &tv);

        if (sel <= 0) {
            close(fd);
            NSString *msg = sel == 0 ? @"Connection timed out" :
                            [NSString stringWithFormat:@"select() failed: %s", strerror(errno)];
            [self _failWithMessage:msg completion:completion];
            return;
        }

        /* Check for socket error */
        int err = 0;
        socklen_t errlen = sizeof(err);
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &errlen);
        if (err != 0) {
            close(fd);
            [self _failWithMessage:[NSString stringWithFormat:@"Connection refused: %s",
                                    strerror(err)]
                        completion:completion];
            return;
        }
    }

    /* Restore blocking mode */
    fcntl(fd, F_SETFL, flags & ~O_NONBLOCK);

    /* Set 2-second send/recv timeouts */
    struct timeval tv2 = { .tv_sec = 2, .tv_usec = 0 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv2, sizeof(tv2));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv2, sizeof(tv2));

    /* Hand socket to VICE */
    self->_sock = fd;
    vice_net2iec_enable(fd);

    dispatch_async(dispatch_get_main_queue(), ^{
        self->_state     = Net2IECStateConnected;
        self->_lastError = nil;
        if (completion) completion(YES, nil);
    });
}

// MARK: - Disconnect

- (void)disconnect {
    vice_net2iec_disable();
    [self _closeSocket];
    _state = Net2IECStateDisconnected;
}

- (void)_closeSocket {
    if (_sock >= 0) {
        close(_sock);
        _sock = -1;
    }
}

// MARK: - Error helper

- (void)_failWithMessage:(NSString *)msg
              completion:(void (^)(BOOL, NSError *_Nullable))completion
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_state     = Net2IECStateError;
        self->_lastError = msg;
        NSError *error = [NSError errorWithDomain:@"Net2IECErrorDomain"
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: msg}];
        if (completion) completion(NO, error);
    });
}

@end
