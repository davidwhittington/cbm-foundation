/* vice_mac_kbd.c
 * NSEvent keyboard input → VICE C64 keyboard matrix translation.
 *
 * Strategy: macOS hardware key codes (NSEvent.keyCode) map to physical key
 * positions on a US layout. We map these to VICE's internal key symbols using
 * a table derived from vice/data/C64/gtk3_pos.vkm (positional layout).
 *
 * VICE's keyboard layer:
 *   keyboard_key_pressed(key, mod)  — called when a key is held down
 *   keyboard_key_released(key, mod) — called when a key is released
 *
 * 'key' is a VICE internal key symbol (defined in vice/src/keyboard.h).
 * 'mod' is a bitmask of KBD_MOD_* values.
 *
 * Phase 2: core table for C64 QWERTY (US positional). Extend for other
 * layouts and machines in Phase 5.
 */

#include "vice_mac_kbd.h"
#include "vice_config.h"
#include "keyboard.h"
#include "log.h"
#include <stdint.h>

static log_t vice_kbd_log = LOG_DEFAULT;

/* ── macOS key code → VICE key symbol table ─────────────────────────────── */
/*
 * macOS hardware key codes (kVK_* constants from Carbon/HIToolbox).
 * These are layout-independent: kVK_ANSI_A is always the 'A' physical key
 * regardless of the user's keyboard layout.
 *
 * VICE key symbols: defined in vice/src/keyboard.h (KBD_KEY_* or H_ prefix).
 * Reference: vice/data/C64/gtk3_pos.vkm maps GDK keysyms by position.
 * We use the GDK→VICE mappings and cross-reference to macOS kVK codes.
 */

/* macOS key codes (subset, from HIToolbox/Events.h) */
#define MAC_KEY_ANSI_A              0x00
#define MAC_KEY_ANSI_S              0x01
#define MAC_KEY_ANSI_D              0x02
#define MAC_KEY_ANSI_F              0x03
#define MAC_KEY_ANSI_H              0x04
#define MAC_KEY_ANSI_G              0x05
#define MAC_KEY_ANSI_Z              0x06
#define MAC_KEY_ANSI_X              0x07
#define MAC_KEY_ANSI_C              0x08
#define MAC_KEY_ANSI_V              0x09
#define MAC_KEY_ANSI_B              0x0B
#define MAC_KEY_ANSI_Q              0x0C
#define MAC_KEY_ANSI_W              0x0D
#define MAC_KEY_ANSI_E              0x0E
#define MAC_KEY_ANSI_R              0x0F
#define MAC_KEY_ANSI_Y              0x10
#define MAC_KEY_ANSI_T              0x11
#define MAC_KEY_ANSI_1              0x12
#define MAC_KEY_ANSI_2              0x13
#define MAC_KEY_ANSI_3              0x14
#define MAC_KEY_ANSI_4              0x15
#define MAC_KEY_ANSI_6              0x16
#define MAC_KEY_ANSI_5              0x17
#define MAC_KEY_ANSI_EQUAL          0x18
#define MAC_KEY_ANSI_9              0x19
#define MAC_KEY_ANSI_7              0x1A
#define MAC_KEY_ANSI_MINUS          0x1B
#define MAC_KEY_ANSI_8              0x1C
#define MAC_KEY_ANSI_0              0x1D
#define MAC_KEY_ANSI_RIGHTBRACKET   0x1E
#define MAC_KEY_ANSI_O              0x1F
#define MAC_KEY_ANSI_U              0x20
#define MAC_KEY_ANSI_LEFTBRACKET    0x21
#define MAC_KEY_ANSI_I              0x22
#define MAC_KEY_ANSI_P              0x23
#define MAC_KEY_RETURN              0x24
#define MAC_KEY_ANSI_L              0x25
#define MAC_KEY_ANSI_J              0x26
#define MAC_KEY_ANSI_QUOTE          0x27
#define MAC_KEY_ANSI_K              0x28
#define MAC_KEY_ANSI_SEMICOLON      0x29
#define MAC_KEY_ANSI_BACKSLASH      0x2A
#define MAC_KEY_ANSI_COMMA          0x2B
#define MAC_KEY_ANSI_SLASH          0x2C
#define MAC_KEY_ANSI_N              0x2D
#define MAC_KEY_ANSI_M              0x2E
#define MAC_KEY_ANSI_PERIOD         0x2F
#define MAC_KEY_TAB                 0x30
#define MAC_KEY_SPACE               0x31
#define MAC_KEY_ANSI_GRAVE          0x32
#define MAC_KEY_DELETE              0x33  /* Backspace */
#define MAC_KEY_ESCAPE              0x35
#define MAC_KEY_LEFTCTRL            0x3B
#define MAC_KEY_LEFTSHIFT           0x38
#define MAC_KEY_RIGHTSHIFT          0x3C
#define MAC_KEY_LEFTALT             0x3A
#define MAC_KEY_LEFTCMD             0x37
#define MAC_KEY_CAPSLOCK            0x39
#define MAC_KEY_F1                  0x7A
#define MAC_KEY_F2                  0x78
#define MAC_KEY_F3                  0x63
#define MAC_KEY_F4                  0x76
#define MAC_KEY_F5                  0x60
#define MAC_KEY_F6                  0x61
#define MAC_KEY_F7                  0x62
#define MAC_KEY_F8                  0x64
#define MAC_KEY_CURSOR_LEFT         0x7B
#define MAC_KEY_CURSOR_RIGHT        0x7C
#define MAC_KEY_CURSOR_DOWN         0x7D
#define MAC_KEY_CURSOR_UP           0x7E
#define MAC_KEY_HOME                0x73
#define MAC_KEY_END                 0x77
#define MAC_KEY_PAGEUP              0x74
#define MAC_KEY_PAGEDOWN            0x79

/* Sentinel for unmapped keys */
#define VICE_KEY_NONE  (-1)

/*
 * Mapping table: [macOS keycode] -> VICE key symbol
 * VICE key symbols from vice/src/keyboard.h (KBD_KEY_* macros).
 * 256-entry table indexed by hardware keycode (0x00–0xFF).
 */
static int s_keymap[256];

static void _build_keymap(void) {
    for (int i = 0; i < 256; i++) s_keymap[i] = VICE_KEY_NONE;

    /* Reference: vice/src/keyboard.h for KBD_KEY_* values.
     * These mappings produce a positional US C64 layout.
     * Extended and verified during Phase 5 testing. */

    /* Row 0: function keys → C64 F-keys */
    s_keymap[MAC_KEY_F1] = KBD_KEY_F1;
    s_keymap[MAC_KEY_F2] = KBD_KEY_F2;  /* Shift+F1 on real C64; we map F2→F2 */
    s_keymap[MAC_KEY_F3] = KBD_KEY_F3;
    s_keymap[MAC_KEY_F4] = KBD_KEY_F4;
    s_keymap[MAC_KEY_F5] = KBD_KEY_F5;
    s_keymap[MAC_KEY_F6] = KBD_KEY_F6;
    s_keymap[MAC_KEY_F7] = KBD_KEY_F7;
    s_keymap[MAC_KEY_F8] = KBD_KEY_F8;

    /* Row 1: number row */
    s_keymap[MAC_KEY_ANSI_GRAVE]    = KBD_KEY_GRAVE;  /* ← → mapped to backtick */
    s_keymap[MAC_KEY_ANSI_1]        = KBD_KEY_1;
    s_keymap[MAC_KEY_ANSI_2]        = KBD_KEY_2;
    s_keymap[MAC_KEY_ANSI_3]        = KBD_KEY_3;
    s_keymap[MAC_KEY_ANSI_4]        = KBD_KEY_4;
    s_keymap[MAC_KEY_ANSI_5]        = KBD_KEY_5;
    s_keymap[MAC_KEY_ANSI_6]        = KBD_KEY_6;
    s_keymap[MAC_KEY_ANSI_7]        = KBD_KEY_7;
    s_keymap[MAC_KEY_ANSI_8]        = KBD_KEY_8;
    s_keymap[MAC_KEY_ANSI_9]        = KBD_KEY_9;
    s_keymap[MAC_KEY_ANSI_0]        = KBD_KEY_0;
    s_keymap[MAC_KEY_ANSI_MINUS]    = KBD_KEY_MINUS;
    s_keymap[MAC_KEY_ANSI_EQUAL]    = KBD_KEY_EQUAL;  /* + on C64 */
    s_keymap[MAC_KEY_DELETE]        = KBD_KEY_DEL;

    /* Row 2: QWERTY */
    s_keymap[MAC_KEY_TAB]           = KBD_KEY_TAB;   /* CTRL on C64 */
    s_keymap[MAC_KEY_ANSI_Q]        = KBD_KEY_Q;
    s_keymap[MAC_KEY_ANSI_W]        = KBD_KEY_W;
    s_keymap[MAC_KEY_ANSI_E]        = KBD_KEY_E;
    s_keymap[MAC_KEY_ANSI_R]        = KBD_KEY_R;
    s_keymap[MAC_KEY_ANSI_T]        = KBD_KEY_T;
    s_keymap[MAC_KEY_ANSI_Y]        = KBD_KEY_Y;
    s_keymap[MAC_KEY_ANSI_U]        = KBD_KEY_U;
    s_keymap[MAC_KEY_ANSI_I]        = KBD_KEY_I;
    s_keymap[MAC_KEY_ANSI_O]        = KBD_KEY_O;
    s_keymap[MAC_KEY_ANSI_P]        = KBD_KEY_P;
    s_keymap[MAC_KEY_ANSI_LEFTBRACKET]  = KBD_KEY_AT;       /* @ on C64 */
    s_keymap[MAC_KEY_ANSI_RIGHTBRACKET] = KBD_KEY_ASTERISK; /* * on C64 */

    /* Row 3: ASDF */
    s_keymap[MAC_KEY_LEFTCTRL]      = KBD_KEY_CTRL;
    s_keymap[MAC_KEY_ANSI_A]        = KBD_KEY_A;
    s_keymap[MAC_KEY_ANSI_S]        = KBD_KEY_S;
    s_keymap[MAC_KEY_ANSI_D]        = KBD_KEY_D;
    s_keymap[MAC_KEY_ANSI_F]        = KBD_KEY_F;
    s_keymap[MAC_KEY_ANSI_G]        = KBD_KEY_G;
    s_keymap[MAC_KEY_ANSI_H]        = KBD_KEY_H;
    s_keymap[MAC_KEY_ANSI_J]        = KBD_KEY_J;
    s_keymap[MAC_KEY_ANSI_K]        = KBD_KEY_K;
    s_keymap[MAC_KEY_ANSI_L]        = KBD_KEY_L;
    s_keymap[MAC_KEY_ANSI_SEMICOLON] = KBD_KEY_COLON;   /* : on C64 */
    s_keymap[MAC_KEY_ANSI_QUOTE]     = KBD_KEY_SEMICOLON; /* ; on C64 */
    s_keymap[MAC_KEY_ANSI_BACKSLASH] = KBD_KEY_EQUAL;   /* = on C64 */
    s_keymap[MAC_KEY_RETURN]         = KBD_KEY_RETURN;

    /* Row 4: ZXCV */
    s_keymap[MAC_KEY_LEFTSHIFT]     = KBD_KEY_LSHIFT;
    s_keymap[MAC_KEY_ANSI_Z]        = KBD_KEY_Z;
    s_keymap[MAC_KEY_ANSI_X]        = KBD_KEY_X;
    s_keymap[MAC_KEY_ANSI_C]        = KBD_KEY_C;
    s_keymap[MAC_KEY_ANSI_V]        = KBD_KEY_V;
    s_keymap[MAC_KEY_ANSI_B]        = KBD_KEY_B;
    s_keymap[MAC_KEY_ANSI_N]        = KBD_KEY_N;
    s_keymap[MAC_KEY_ANSI_M]        = KBD_KEY_M;
    s_keymap[MAC_KEY_ANSI_COMMA]    = KBD_KEY_COMMA;
    s_keymap[MAC_KEY_ANSI_PERIOD]   = KBD_KEY_PERIOD;
    s_keymap[MAC_KEY_ANSI_SLASH]    = KBD_KEY_SLASH;
    s_keymap[MAC_KEY_RIGHTSHIFT]    = KBD_KEY_RSHIFT;

    /* Row 5: bottom row */
    s_keymap[MAC_KEY_LEFTCMD]       = KBD_KEY_CBM;    /* Commodore key */
    s_keymap[MAC_KEY_SPACE]         = KBD_KEY_SPACE;

    /* Cursor keys */
    s_keymap[MAC_KEY_CURSOR_LEFT]   = KBD_KEY_LEFT;
    s_keymap[MAC_KEY_CURSOR_RIGHT]  = KBD_KEY_RIGHT;
    s_keymap[MAC_KEY_CURSOR_UP]     = KBD_KEY_UP;
    s_keymap[MAC_KEY_CURSOR_DOWN]   = KBD_KEY_DOWN;

    /* Special */
    s_keymap[MAC_KEY_HOME]          = KBD_KEY_HOME;
    s_keymap[MAC_KEY_ESCAPE]        = KBD_KEY_RUNSTOP;
    s_keymap[MAC_KEY_CAPSLOCK]      = KBD_KEY_SHIFTLOCK;
    s_keymap[MAC_KEY_LEFTALT]       = KBD_KEY_RESTORE;
}

/* ── Public API ─────────────────────────────────────────────────────────── */

void vice_mac_kbd_init(void) {
    vice_kbd_log = log_open("VICEMacKbd");
    _build_keymap();
    log_message(vice_kbd_log, "Keyboard initialised (US positional layout).");
}

void vice_mac_key_event(uint16_t macKeyCode, uint32_t modifiers, int down) {
    if (macKeyCode >= 256) return;

    int viceKey = s_keymap[macKeyCode];
    if (viceKey == VICE_KEY_NONE) return;

    /* Translate modifier flags to VICE KBD_MOD_* bitmask */
    int viceMod = 0;
    if (modifiers & (1 << 17)) viceMod |= KBD_MOD_LSHIFT;   /* NSShiftKeyMask */
    if (modifiers & (1 << 18)) viceMod |= KBD_MOD_RSHIFT;
    if (modifiers & (1 << 12)) viceMod |= KBD_MOD_LCTRL;    /* NSControlKeyMask */
    if (modifiers & (1 << 11)) viceMod |= KBD_MOD_LALT;     /* NSAlternateKeyMask */

    if (down) {
        keyboard_key_pressed((signed long)viceKey, viceMod);
    } else {
        keyboard_key_released((signed long)viceKey, viceMod);
    }
}
