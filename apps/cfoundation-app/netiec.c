/* netiec.c — NetIEC Protocol Stub Implementation
 *
 * STATUS: SCAFFOLD
 * The interface (netiec.h) is defined. This file contains stubs
 * that allow c=foundation to compile and run without FujiNet-PC.
 *
 * When FujiNet-PC's IEC server is available and the protocol is finalised,
 * replace each stub with the real implementation:
 *   - netiec_init():   bind UDP socket, start rx pthread (model on netsio.c)
 *   - netiec_shutdown(): signal thread, join, close socket
 *   - device callbacks: relay open/close/get/put over UDP to FujiNet-PC
 *
 * Until then, device callbacks return SERIAL_ERROR so VICE falls back
 * to its built-in virtual device layer.
 */

#include "netiec.h"
#include <stdio.h>

/* SERIAL_ERROR: borrowed from vice/src/serial.h */
#ifndef SERIAL_ERROR
#define SERIAL_ERROR 0x80
#endif
#ifndef SERIAL_OK
#define SERIAL_OK 0
#endif

static int  _enabled   = 0;
static int  _connected = 0;

/* ── Lifecycle ──────────────────────────────────────────────────────────── */

int netiec_init(uint16_t port) {
    (void)port;
    fprintf(stderr, "[NetIEC] stub: init() called (port %u). "
                    "FujiNet-PC IEC server not yet available.\n", port);
    _enabled = 1;
    return 0;  /* report success so the app can start */
}

void netiec_shutdown(void) {
    fprintf(stderr, "[NetIEC] stub: shutdown() called.\n");
    _enabled   = 0;
    _connected = 0;
}

/* ── Status ─────────────────────────────────────────────────────────────── */

int netiec_is_connected(void) { return _connected; }
int netiec_is_enabled(void)   { return _enabled;   }

/* ── VICE serial_t device callbacks ─────────────────────────────────────── */

int netiec_device_open(unsigned int device, unsigned int secondary) {
    /* TODO: send NETIEC_BYTE_TO_DEVICE for OPEN command frame */
    (void)device; (void)secondary;
    return SERIAL_ERROR;  /* fallback to VICE virtual device */
}

int netiec_device_close(unsigned int device, unsigned int secondary) {
    (void)device; (void)secondary;
    return SERIAL_ERROR;
}

int netiec_device_put(unsigned int device, uint8_t byte, unsigned int secondary) {
    (void)device; (void)byte; (void)secondary;
    return SERIAL_ERROR;
}

int netiec_device_get(unsigned int device, uint8_t *byte, unsigned int secondary) {
    (void)device; (void)secondary;
    if (byte) *byte = 0;
    return SERIAL_ERROR;
}

/* ── Reset notification ─────────────────────────────────────────────────── */

void netiec_warm_reset(void) {
    /* TODO: send NETIEC_WARM_RESET to FujiNet-PC */
}

void netiec_cold_reset(void) {
    /* TODO: send NETIEC_COLD_RESET to FujiNet-PC */
}
