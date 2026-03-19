/* vice_mac_joystick.m
 * GameController framework integration for c=foundation.
 *
 * Architecture:
 *   - GCController callbacks (any thread) → atomic uint16_t _joy_state[2]
 *   - vice_mac_joystick_poll() (VICE thread) → joystick_set_value_absolute()
 *
 * VICE joystick port bit layout (joyport/joystick.h):
 *   bit 0 = Up       (1)
 *   bit 1 = Down     (2)
 *   bit 2 = Left     (4)
 *   bit 3 = Right    (8)
 *   bit 4 = Fire     (16)
 *
 * Controller mapping:
 *   First connected controller  → Port 2 (index 0)
 *   Second connected controller → Port 1 (index 1)
 *
 * Axis dead zone: values below this threshold are treated as centred.
 */

#import <GameController/GameController.h>
#import <stdatomic.h>

#include "vice_mac_joystick.h"
#include "joyport/joystick.h"
#include "log.h"

#define JOYSTICK_DEADZONE  0.25f

/* VICE ports: 0-indexed internally, 1-indexed in VICE API.
 * Default: first controller → port 2 (most C64 games use port 2).
 * When _joy_swap=1: first controller → port 1. */
#define NUM_JOY_PORTS  2

static log_t vice_joy_log = LOG_DEFAULT;

/* Atomic joystick state — GCController callbacks write, VICE thread reads */
static _Atomic uint16_t _joy_state[NUM_JOY_PORTS];
static _Atomic uint16_t _joy_prev[NUM_JOY_PORTS];
static _Atomic int      _joy_swap = 0;

static inline unsigned int _vice_port_for_idx(int idx) {
    int swapped = atomic_load_explicit(&_joy_swap, memory_order_relaxed);
    /* default: idx0→port2, idx1→port1; swapped: idx0→port1, idx1→port2 */
    return (unsigned int)(((idx == 0) ^ swapped) ? 2 : 1);
}

/* ── Internal helpers ───────────────────────────────────────────────────── */

static uint16_t _gamepad_to_vice(GCExtendedGamepad *pad)
{
    uint16_t val = 0;

    /* D-pad (digital) */
    if (pad.dpad.up.isPressed)    val |= 1;  /* JOYSTICK_DIRECTION_UP    */
    if (pad.dpad.down.isPressed)  val |= 2;  /* JOYSTICK_DIRECTION_DOWN  */
    if (pad.dpad.left.isPressed)  val |= 4;  /* JOYSTICK_DIRECTION_LEFT  */
    if (pad.dpad.right.isPressed) val |= 8;  /* JOYSTICK_DIRECTION_RIGHT */

    /* Left thumbstick — treat as an 8-way stick with a dead zone */
    float lx = pad.leftThumbstick.xAxis.value;
    float ly = pad.leftThumbstick.yAxis.value;
    if (ly >  JOYSTICK_DEADZONE) val |= 1;
    if (ly < -JOYSTICK_DEADZONE) val |= 2;
    if (lx < -JOYSTICK_DEADZONE) val |= 4;
    if (lx >  JOYSTICK_DEADZONE) val |= 8;

    /* Fire: button A (south), right shoulder, or right trigger */
    if (pad.buttonA.isPressed)             val |= 0x10;
    if (pad.rightShoulder.isPressed)       val |= 0x10;
    if (pad.rightTrigger.value > 0.25f)    val |= 0x10;

    return val;
}

static void _install_handler(GCController *controller, int port_idx)
{
    GCExtendedGamepad *pad = controller.extendedGamepad;
    if (!pad) {
        log_message(vice_joy_log, "Controller \"%s\" has no extendedGamepad, skipped.",
                    controller.vendorName.UTF8String ?: "unknown");
        return;
    }

    log_message(vice_joy_log, "Controller \"%s\" → VICE port %d",
                controller.vendorName.UTF8String ?: "unknown",
                _vice_port_for_idx(port_idx));

    /* Capture port_idx by value inside the block */
    int idx = port_idx;
    pad.valueChangedHandler = ^(GCExtendedGamepad *p, GCControllerElement *element) {
        (void)element;
        uint16_t state = _gamepad_to_vice(p);
        atomic_store_explicit(&_joy_state[idx], state, memory_order_relaxed);
    };
}

static void _connect_controllers(void)
{
    NSArray<GCController *> *controllers = [GCController controllers];
    int port_idx = 0;
    for (GCController *c in controllers) {
        if (port_idx >= NUM_JOY_PORTS) break;
        _install_handler(c, port_idx++);
    }
}

/* ── Public API ─────────────────────────────────────────────────────────── */

void vice_mac_joystick_init(void)
{
    vice_joy_log = log_open("VICEMacJoy");

    for (int i = 0; i < NUM_JOY_PORTS; i++) {
        atomic_store(&_joy_state[i], 0);
        atomic_store(&_joy_prev[i],  0);
    }

    /* Wire up already-connected controllers */
    _connect_controllers();

    /* Observer: controller connected */
    [[NSNotificationCenter defaultCenter]
        addObserverForName:GCControllerDidConnectNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        (void)note;
        _connect_controllers();
        log_message(vice_joy_log, "Controller connected.");
    }];

    /* Observer: controller disconnected — reset all port state */
    [[NSNotificationCenter defaultCenter]
        addObserverForName:GCControllerDidDisconnectNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        (void)note;
        for (int i = 0; i < NUM_JOY_PORTS; i++) {
            atomic_store(&_joy_state[i], 0);
        }
        _connect_controllers();
        log_message(vice_joy_log, "Controller disconnected.");
    }];

    log_message(vice_joy_log, "Joystick subsystem initialised (%d port(s)).", NUM_JOY_PORTS);
}

void vice_mac_joystick_poll(void)
{
    for (int i = 0; i < NUM_JOY_PORTS; i++) {
        uint16_t cur  = atomic_load_explicit(&_joy_state[i], memory_order_relaxed);
        uint16_t prev = atomic_load_explicit(&_joy_prev[i],  memory_order_relaxed);
        if (cur != prev) {
            joystick_set_value_absolute(_vice_port_for_idx(i), cur);
            atomic_store_explicit(&_joy_prev[i], cur, memory_order_relaxed);
        }
    }
}

void vice_mac_joystick_set_port_swap(int swapped)
{
    atomic_store_explicit(&_joy_swap, swapped ? 1 : 0, memory_order_relaxed);
    /* Clear state so stale values don't persist across the swap */
    for (int i = 0; i < NUM_JOY_PORTS; i++) {
        atomic_store(&_joy_state[i], 0);
        atomic_store(&_joy_prev[i],  0);
    }
    log_message(vice_joy_log, "Joystick ports %s.", swapped ? "swapped (P1↔P2)" : "restored to default");
}

void vice_mac_joystick_shutdown(void)
{
    [[NSNotificationCenter defaultCenter]
        removeObserver:nil
                  name:GCControllerDidConnectNotification
                object:nil];
    [[NSNotificationCenter defaultCenter]
        removeObserver:nil
                  name:GCControllerDidDisconnectNotification
                object:nil];
    for (int i = 0; i < NUM_JOY_PORTS; i++) {
        atomic_store(&_joy_state[i], 0);
        atomic_store(&_joy_prev[i],  0);
    }
}
