/* vice_net2iec.h
 * Net2IEC driver — forwards VICE IEC bus operations to a TCP socket.
 * Implements CBM-NET v1 binary protocol.
 *
 * Protocol (binary, framed):
 *   Request:  [OPCODE:1][UNIT:1][SA:1][PAYLOAD_LEN:2LE][PAYLOAD:N]
 *   Response: [STATUS:1][PAYLOAD_LEN:2LE][PAYLOAD:N]
 *
 *   OPCODE: 0x01=OPEN  0x02=CLOSE  0x03=READ  0x04=WRITE  0x05=FLUSH
 *   STATUS: 0x00=OK    0x40=EOF    0x80=ERROR
 */
#pragma once
#include <stdint.h>

/* Initialise net2iec subsystem (called from vice_mac_sdl.m ui_init_finalize). */
void vice_net2iec_init(void);

/* Attach a connected TCP socket to IEC units 8-11.
 * sock must be a connected, blocking POSIX socket.
 * After this call the VICE thread owns the socket for I/O. */
void vice_net2iec_enable(int sock);

/* Detach from all units and stop using the socket.
 * Caller is responsible for closing the fd after this returns. */
void vice_net2iec_disable(void);

/* Returns 1 if net2iec is currently active (socket >= 0). */
int vice_net2iec_active(void);
