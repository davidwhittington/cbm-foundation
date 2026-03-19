/* vice_net2iec.c
 * Net2IEC TCP bridge — forwards VICE IEC bus operations to a remote
 * Meatloaf/FujiNet-PC server using the CBM-NET v1 binary protocol.
 *
 * Threading:
 *   - Main thread (ObjC) creates the TCP socket and calls vice_net2iec_enable().
 *   - After enable(), the VICE thread owns the fd for all I/O.
 *   - g_sock is _Atomic; the main thread atomically clears it to -1 via
 *     vice_net2iec_disable() before the caller closes the fd.
 *
 * Graceful fallback:
 *   If g_sock == -1, all callbacks return CBM error 74 ("drive not ready").
 */

#include "vice_net2iec.h"

#include "vice.h"
#include "log.h"
#include "machine-bus.h"
#include "serial.h"
#include "vdrive/vdrive.h"

#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <stdatomic.h>

/* ── Protocol constants ──────────────────────────────────────────────── */

#define N2I_OP_OPEN   0x01
#define N2I_OP_CLOSE  0x02
#define N2I_OP_READ   0x03
#define N2I_OP_WRITE  0x04
#define N2I_OP_FLUSH  0x05

#define N2I_ST_OK     0x00
#define N2I_ST_EOF    0x40
#define N2I_ST_ERROR  0x80

#define N2I_READ_CHUNK 64  /* bytes per READ request */

/* CBM error 74 = "DRIVE NOT READY" */
#define CBM_ERR_NOT_READY  0x80  /* SERIAL_ERROR equivalent */

/* VICE serial status codes (defined in serial.h via SERIAL_ERROR / SERIAL_OK) */
#ifndef SERIAL_OK
#define SERIAL_OK     0x00
#endif
#ifndef SERIAL_ERROR
#define SERIAL_ERROR  0x80
#endif
#ifndef SERIAL_EOF
#define SERIAL_EOF    0x40
#endif

/* ── State ───────────────────────────────────────────────────────────── */

static log_t net2iec_log = LOG_DEFAULT;

/* Socket fd; -1 = not connected.  Written by main thread, read by VICE thread. */
static _Atomic int g_sock = -1;

/* Per-secondary read buffer: 4 units (8-11) × 16 secondaries */
#define N2I_UNITS      4
#define N2I_SECONDARY  16

typedef struct {
    uint8_t buf[256];
    int     pos;
    int     len;
    int     eof;
} ReadBuf;

static ReadBuf g_rbuf[N2I_UNITS][N2I_SECONDARY];

/* Map unit number (8-11) to array index */
static inline int unit_idx(unsigned int unit) {
    return (int)(unit - 8);
}

/* ── Low-level send/recv helpers ─────────────────────────────────────── */

/* Send exactly n bytes; returns 0 on success, -1 on error. */
static int n2i_send_all(int fd, const uint8_t *buf, int n)
{
    while (n > 0) {
        ssize_t sent = send(fd, buf, (size_t)n, 0);
        if (sent <= 0) return -1;
        buf += sent;
        n   -= (int)sent;
    }
    return 0;
}

/* Recv exactly n bytes; returns 0 on success, -1 on error. */
static int n2i_recv_all(int fd, uint8_t *buf, int n)
{
    while (n > 0) {
        ssize_t got = recv(fd, buf, (size_t)n, 0);
        if (got <= 0) return -1;
        buf += got;
        n   -= (int)got;
    }
    return 0;
}

/* ── Protocol encode/decode ──────────────────────────────────────────── */

/*
 * Send a request frame:
 *   [OPCODE:1][UNIT:1][SA:1][PAYLOAD_LEN:2LE][PAYLOAD:N]
 */
static int n2i_send_request(int fd,
                             uint8_t opcode,
                             uint8_t unit,
                             uint8_t sa,
                             const uint8_t *payload,
                             uint16_t plen)
{
    uint8_t hdr[5];
    hdr[0] = opcode;
    hdr[1] = unit;
    hdr[2] = sa;
    hdr[3] = (uint8_t)(plen & 0xFF);
    hdr[4] = (uint8_t)((plen >> 8) & 0xFF);

    if (n2i_send_all(fd, hdr, 5) < 0) return -1;
    if (plen > 0 && payload) {
        if (n2i_send_all(fd, payload, (int)plen) < 0) return -1;
    }
    return 0;
}

/*
 * Receive a response frame:
 *   [STATUS:1][PAYLOAD_LEN:2LE][PAYLOAD:N]
 * payload_out must be at least 65535 bytes if used; pass NULL to discard.
 * Returns the STATUS byte, or -1 on socket error.
 */
static int n2i_recv_response(int fd, uint8_t *payload_out, uint16_t *payload_len_out)
{
    uint8_t hdr[3];
    if (n2i_recv_all(fd, hdr, 3) < 0) return -1;

    uint8_t  status = hdr[0];
    uint16_t plen   = (uint16_t)(hdr[1] | ((uint16_t)hdr[2] << 8));

    if (payload_len_out) *payload_len_out = plen;

    if (plen > 0) {
        if (payload_out) {
            if (n2i_recv_all(fd, payload_out, (int)plen) < 0) return -1;
        } else {
            /* discard */
            uint8_t discard[256];
            int remaining = (int)plen;
            while (remaining > 0) {
                int chunk = remaining > 256 ? 256 : remaining;
                if (n2i_recv_all(fd, discard, chunk) < 0) return -1;
                remaining -= chunk;
            }
        }
    }
    return (int)(status & 0xFF);
}

/* ── IEC bus callbacks ───────────────────────────────────────────────── */

static int n2i_openf(struct vdrive_s *vdrive,
                     const uint8_t *name, unsigned int length,
                     unsigned int secondary,
                     struct cbmdos_cmd_parse_s *cmd_parse)
{
    (void)cmd_parse;
    int fd = atomic_load(&g_sock);
    if (fd < 0) return CBM_ERR_NOT_READY;

    unsigned int unit = vdrive->unit;
    int ui = unit_idx(unit);
    if (ui < 0 || ui >= N2I_UNITS) return CBM_ERR_NOT_READY;

    /* Reset read buffer for this secondary */
    memset(&g_rbuf[ui][secondary & 0x0F], 0, sizeof(ReadBuf));

    if (n2i_send_request(fd, N2I_OP_OPEN,
                         (uint8_t)unit, (uint8_t)secondary,
                         name, (uint16_t)length) < 0) {
        log_error(net2iec_log, "net2iec: OPEN send failed (unit %u, sa %u)",
                  unit, secondary);
        atomic_store(&g_sock, -1);
        return CBM_ERR_NOT_READY;
    }

    int status = n2i_recv_response(fd, NULL, NULL);
    if (status < 0) {
        log_error(net2iec_log, "net2iec: OPEN recv failed");
        atomic_store(&g_sock, -1);
        return CBM_ERR_NOT_READY;
    }
    if (status == N2I_ST_ERROR) return CBM_ERR_NOT_READY;
    return SERIAL_OK;
}

static int n2i_closef(struct vdrive_s *vdrive, unsigned int secondary)
{
    int fd = atomic_load(&g_sock);
    if (fd < 0) return CBM_ERR_NOT_READY;

    unsigned int unit = vdrive->unit;
    int ui = unit_idx(unit);
    if (ui >= 0 && ui < N2I_UNITS) {
        memset(&g_rbuf[ui][secondary & 0x0F], 0, sizeof(ReadBuf));
    }

    if (n2i_send_request(fd, N2I_OP_CLOSE,
                         (uint8_t)unit, (uint8_t)secondary,
                         NULL, 0) < 0) {
        atomic_store(&g_sock, -1);
        return CBM_ERR_NOT_READY;
    }
    n2i_recv_response(fd, NULL, NULL);  /* best-effort */
    return SERIAL_OK;
}

static int n2i_getf(struct vdrive_s *vdrive, uint8_t *byte, unsigned int secondary)
{
    int fd = atomic_load(&g_sock);
    if (fd < 0) return CBM_ERR_NOT_READY;

    unsigned int unit = vdrive->unit;
    int ui = unit_idx(unit);
    if (ui < 0 || ui >= N2I_UNITS) return CBM_ERR_NOT_READY;

    int sa = (int)(secondary & 0x0F);
    ReadBuf *rb = &g_rbuf[ui][sa];

    /* If buffer empty, issue a new READ request */
    if (rb->pos >= rb->len) {
        if (rb->eof) {
            *byte = 0;
            return SERIAL_EOF;
        }

        uint8_t count_payload[2];
        count_payload[0] = (uint8_t)(N2I_READ_CHUNK & 0xFF);
        count_payload[1] = (uint8_t)((N2I_READ_CHUNK >> 8) & 0xFF);

        if (n2i_send_request(fd, N2I_OP_READ,
                             (uint8_t)unit, (uint8_t)secondary,
                             count_payload, 2) < 0) {
            atomic_store(&g_sock, -1);
            return CBM_ERR_NOT_READY;
        }

        uint16_t plen = 0;
        int status = n2i_recv_response(fd, rb->buf, &plen);
        if (status < 0) {
            atomic_store(&g_sock, -1);
            return CBM_ERR_NOT_READY;
        }

        rb->pos = 0;
        rb->len = (int)plen;

        if (status == N2I_ST_EOF) {
            rb->eof = 1;
        } else if (status == N2I_ST_ERROR) {
            rb->pos = rb->len = 0;
            *byte = 0;
            return CBM_ERR_NOT_READY;
        }

        if (rb->len == 0) {
            *byte = 0;
            return rb->eof ? SERIAL_EOF : CBM_ERR_NOT_READY;
        }
    }

    *byte = rb->buf[rb->pos++];

    /* Signal EOF on last byte if server said EOF */
    if (rb->eof && rb->pos >= rb->len) {
        return SERIAL_EOF;
    }
    return SERIAL_OK;
}

static int n2i_putf(struct vdrive_s *vdrive, uint8_t byte, unsigned int secondary)
{
    int fd = atomic_load(&g_sock);
    if (fd < 0) return CBM_ERR_NOT_READY;

    unsigned int unit = vdrive->unit;

    if (n2i_send_request(fd, N2I_OP_WRITE,
                         (uint8_t)unit, (uint8_t)secondary,
                         &byte, 1) < 0) {
        atomic_store(&g_sock, -1);
        return CBM_ERR_NOT_READY;
    }

    int status = n2i_recv_response(fd, NULL, NULL);
    if (status < 0) {
        atomic_store(&g_sock, -1);
        return CBM_ERR_NOT_READY;
    }
    return (status == N2I_ST_ERROR) ? CBM_ERR_NOT_READY : SERIAL_OK;
}

static void n2i_flushf(struct vdrive_s *vdrive, unsigned int secondary)
{
    int fd = atomic_load(&g_sock);
    if (fd < 0) return;

    unsigned int unit = vdrive->unit;

    if (n2i_send_request(fd, N2I_OP_FLUSH,
                         (uint8_t)unit, (uint8_t)secondary,
                         NULL, 0) < 0) {
        atomic_store(&g_sock, -1);
        return;
    }
    n2i_recv_response(fd, NULL, NULL);  /* best-effort */
}

static void n2i_listenf(struct vdrive_s *vdrive, unsigned int secondary)
{
    /* Nothing extra to do for listen; the open/write sequence handles it. */
    (void)vdrive; (void)secondary;
}

/* ── Public API ──────────────────────────────────────────────────────── */

void vice_net2iec_init(void)
{
    net2iec_log = log_open("Net2IEC");
    atomic_store(&g_sock, -1);
    memset(g_rbuf, 0, sizeof(g_rbuf));
    log_message(net2iec_log, "net2iec subsystem initialised.");
}

void vice_net2iec_enable(int sock)
{
    if (sock < 0) return;

    /* Set 2-second receive timeout on the socket */
    struct timeval tv;
    tv.tv_sec  = 2;
    tv.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    /* Clear all read buffers */
    memset(g_rbuf, 0, sizeof(g_rbuf));

    /* Store socket — must happen before attaching devices */
    atomic_store(&g_sock, sock);

    /* Attach to units 8-11 */
    for (unsigned int unit = 8; unit <= 11; unit++) {
        machine_bus_device_attach(unit, "net2iec",
                                  n2i_getf,
                                  n2i_putf,
                                  n2i_openf,
                                  n2i_closef,
                                  n2i_flushf,
                                  n2i_listenf);
        serial_device_type_set(SERIAL_DEVICE_FS, unit);
    }

    log_message(net2iec_log, "net2iec enabled on units 8-11 (fd=%d).", sock);
}

void vice_net2iec_disable(void)
{
    /* Clear socket first — VICE callbacks will return CBM_ERR_NOT_READY */
    atomic_store(&g_sock, -1);

    /* Detach from IEC bus */
    for (unsigned int unit = 8; unit <= 11; unit++) {
        machine_bus_device_detach(unit);
    }

    /* Clear all read buffers */
    memset(g_rbuf, 0, sizeof(g_rbuf));

    log_message(net2iec_log, "net2iec disabled.");
}

int vice_net2iec_active(void)
{
    return atomic_load(&g_sock) >= 0 ? 1 : 0;
}
