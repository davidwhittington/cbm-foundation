/* netiec.h — NetIEC Protocol
 * UDP bridge between c=foundation's VICE IEC bus and the FujiNet-PC daemon.
 *
 * STATUS: SCAFFOLD
 * The interface is defined and the message IDs are specified.
 * The UDP transport and IEC device callbacks are NOT yet implemented.
 * When FujiNet-PC's IEC server is available, implement netiec.c against this header.
 *
 * Modeled on netsio.h from fuji-foundation, adapted for the Commodore IEC bus.
 *
 * IEC vs SIO differences:
 *   - IEC is a multi-drop bit-serial bus (ATN, CLK, DATA, RESET lines)
 *   - NetIEC intercepts at the serial_t device callback level (open/close/get/put)
 *     rather than the raw bus level; bus-level intercept is a future enhancement
 *   - Default port: 6400 (configure in Network preferences)
 */

#ifndef NETIEC_H
#define NETIEC_H

#include <stdint.h>
#include <stddef.h>

/* Protocol version tag included in every message */
#define NETIEC_PROTOCOL_VERSION  1

/* Default UDP port (FujiNet-PC IEC listener) */
#define NETIEC_DEFAULT_PORT      6400

/* ── Message IDs ────────────────────────────────────────────────────────── */

/* Bus line state (future: bus-level intercept) */
#define NETIEC_ATN_ASSERT        0x10  /* ATN asserted (host addressing) */
#define NETIEC_ATN_RELEASE       0x11
#define NETIEC_CLK_ASSERT        0x12
#define NETIEC_CLK_RELEASE       0x13
#define NETIEC_DATA_ASSERT       0x14
#define NETIEC_DATA_RELEASE      0x15

/* Data transfer (device-level intercept) */
#define NETIEC_BYTE_TO_DEVICE    0x20  /* host→device: one byte */
#define NETIEC_BYTE_FROM_DEVICE  0x21  /* device→host: one byte */
#define NETIEC_EOI               0x22  /* end-of-information marker */
#define NETIEC_BLOCK_TO_DEVICE   0x28  /* host→device: multi-byte block */
#define NETIEC_BLOCK_FROM_DEVICE 0x29  /* device→host: multi-byte block */

/* Connection management (mirrors NetSIO pattern) */
#define NETIEC_DEVICE_CONNECTED    0xC1
#define NETIEC_DEVICE_DISCONNECTED 0xC0
#define NETIEC_PING_REQUEST        0xC2
#define NETIEC_PING_RESPONSE       0xC3
#define NETIEC_ALIVE_REQUEST       0xC4
#define NETIEC_ALIVE_RESPONSE      0xC5

/* Reset signals */
#define NETIEC_WARM_RESET          0xFE
#define NETIEC_COLD_RESET          0xFF

/* ── Message struct ─────────────────────────────────────────────────────── */

typedef struct NetIECMsg {
    uint8_t  version;     /* NETIEC_PROTOCOL_VERSION */
    uint8_t  id;          /* one of NETIEC_* above */
    uint8_t  device;      /* target device address 8–15; 0 = broadcast */
    uint8_t  secondary;   /* secondary address (channel) */
    uint8_t  arg[512];
    size_t   arg_len;
    double   tstamp;      /* host monotonic timestamp (seconds) */
} NetIECMsg;

/* ── Lifecycle ──────────────────────────────────────────────────────────── */

/**
 * Initialise the NetIEC subsystem.
 * Binds a UDP socket and starts the receive thread.
 * @param port  UDP port of the FujiNet-PC IEC listener (typically NETIEC_DEFAULT_PORT).
 * @return 0 on success, non-zero on error.
 *
 * SCAFFOLD: Not yet implemented. Returns 0 and logs a warning.
 */
int  netiec_init(uint16_t port);

/**
 * Shut down NetIEC: signal the rx thread to exit, join it, close the socket.
 * SCAFFOLD: Not yet implemented.
 */
void netiec_shutdown(void);

/* ── Status ─────────────────────────────────────────────────────────────── */

/** Returns 1 if FujiNet-PC has acknowledged the connection. */
int  netiec_is_connected(void);

/** Returns 1 if NetIEC is initialised and enabled. */
int  netiec_is_enabled(void);

/* ── VICE serial_t device callbacks ─────────────────────────────────────── */
/*
 * These are registered with VICE's serial layer for units 8–11 when NetIEC is enabled.
 * Reference: vice/src/serial.h, serial_device_type_set() and the serial_t struct.
 *
 * SCAFFOLD: Device callbacks exist as stubs. Wire these to the UDP transport
 * once FujiNet-PC's IEC server defines the expected message exchange.
 */

/**
 * Called when the C64 opens a channel to an IEC device.
 * Maps to the OPEN command in the Commodore serial protocol.
 */
int  netiec_device_open(unsigned int device, unsigned int secondary);

/**
 * Called when the C64 closes a channel.
 */
int  netiec_device_close(unsigned int device, unsigned int secondary);

/**
 * Called when the C64 sends a byte to the device (LISTEN/DATA).
 */
int  netiec_device_put(unsigned int device, uint8_t byte, unsigned int secondary);

/**
 * Called when the C64 reads a byte from the device (TALK).
 * Returns the byte in *byte; returns SERIAL_OK or SERIAL_ERROR.
 */
int  netiec_device_get(unsigned int device, uint8_t *byte, unsigned int secondary);

/* ── Reset notification ─────────────────────────────────────────────────── */

void netiec_warm_reset(void);
void netiec_cold_reset(void);

/*
 * FUTURE — Bus-level intercept (not yet designed):
 *
 * void    netiec_bus_write_hook(uint8_t data, unsigned long clk);
 * uint8_t netiec_bus_read_hook(unsigned long clk);
 *
 * These would replace iecbus_callback_read/write for raw bus-level bridging.
 * The serial device intercept above is simpler and sufficient for initial integration.
 */

#endif /* NETIEC_H */
