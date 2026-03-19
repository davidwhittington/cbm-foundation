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
#include "keymap.h"
#include "kbd.h"
#include "vhkkeysyms.h"
#include "log.h"
#include <stdint.h>
#include <stdio.h>

/* X11 keysyms used below that have no VHK_KEY_* alias */
#define X11_KEY_Shift_L     0xffe1
#define X11_KEY_Shift_R     0xffe2
#define X11_KEY_Control_L   0xffe3
#define X11_KEY_Alt_L       0xffe9
#define X11_KEY_Caps_Lock   0xffe5
#define X11_KEY_Right       0xff53
#define X11_KEY_Up          0xff52
#define X11_KEY_Down        0xff54
#define X11_KEY_End         0xff57

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

    /* Row 0: function keys → C64 F-keys (VHK_KEY_F1 = 0xffbe, F2..F8 sequential) */
    s_keymap[MAC_KEY_F1] = VHK_KEY_F1;
    s_keymap[MAC_KEY_F2] = VHK_KEY_F1 + 1;  /* F2 */
    s_keymap[MAC_KEY_F3] = VHK_KEY_F1 + 2;  /* F3 */
    s_keymap[MAC_KEY_F4] = VHK_KEY_F1 + 3;  /* F4 */
    s_keymap[MAC_KEY_F5] = VHK_KEY_F1 + 4;  /* F5 */
    s_keymap[MAC_KEY_F6] = VHK_KEY_F1 + 5;  /* F6 */
    s_keymap[MAC_KEY_F7] = VHK_KEY_F1 + 6;  /* F7 */
    s_keymap[MAC_KEY_F8] = VHK_KEY_F1 + 7;  /* F8 */

    /* Row 1: number row */
    s_keymap[MAC_KEY_ANSI_GRAVE]    = 0x60;  /* grave accent — C64 ← (left arrow) */
    s_keymap[MAC_KEY_ANSI_1]        = '1';
    s_keymap[MAC_KEY_ANSI_2]        = '2';
    s_keymap[MAC_KEY_ANSI_3]        = '3';
    s_keymap[MAC_KEY_ANSI_4]        = '4';
    s_keymap[MAC_KEY_ANSI_5]        = '5';
    s_keymap[MAC_KEY_ANSI_6]        = '6';
    s_keymap[MAC_KEY_ANSI_7]        = '7';
    s_keymap[MAC_KEY_ANSI_8]        = '8';
    s_keymap[MAC_KEY_ANSI_9]        = '9';
    s_keymap[MAC_KEY_ANSI_0]        = '0';
    s_keymap[MAC_KEY_ANSI_MINUS]    = '-';
    s_keymap[MAC_KEY_ANSI_EQUAL]    = '=';   /* + on C64 */
    s_keymap[MAC_KEY_DELETE]        = VHK_KEY_BackSpace;

    /* Row 2: QWERTY — X11 keysyms for letters = ASCII lowercase */
    s_keymap[MAC_KEY_TAB]           = VHK_KEY_Tab;
    s_keymap[MAC_KEY_ANSI_Q]        = 'q';
    s_keymap[MAC_KEY_ANSI_W]        = 'w';
    s_keymap[MAC_KEY_ANSI_E]        = 'e';
    s_keymap[MAC_KEY_ANSI_R]        = 'r';
    s_keymap[MAC_KEY_ANSI_T]        = 't';
    s_keymap[MAC_KEY_ANSI_Y]        = 'y';
    s_keymap[MAC_KEY_ANSI_U]        = 'u';
    s_keymap[MAC_KEY_ANSI_I]        = 'i';
    s_keymap[MAC_KEY_ANSI_O]        = 'o';
    s_keymap[MAC_KEY_ANSI_P]        = 'p';
    s_keymap[MAC_KEY_ANSI_LEFTBRACKET]  = '@';  /* @ on C64 */
    s_keymap[MAC_KEY_ANSI_RIGHTBRACKET] = '*';  /* * on C64 */

    /* Row 3: ASDF */
    s_keymap[MAC_KEY_LEFTCTRL]      = X11_KEY_Control_L;
    s_keymap[MAC_KEY_ANSI_A]        = 'a';
    s_keymap[MAC_KEY_ANSI_S]        = 's';
    s_keymap[MAC_KEY_ANSI_D]        = 'd';
    s_keymap[MAC_KEY_ANSI_F]        = 'f';
    s_keymap[MAC_KEY_ANSI_G]        = 'g';
    s_keymap[MAC_KEY_ANSI_H]        = 'h';
    s_keymap[MAC_KEY_ANSI_J]        = 'j';
    s_keymap[MAC_KEY_ANSI_K]        = 'k';
    s_keymap[MAC_KEY_ANSI_L]        = 'l';
    s_keymap[MAC_KEY_ANSI_SEMICOLON] = ':';  /* : on C64 */
    s_keymap[MAC_KEY_ANSI_QUOTE]     = ';';  /* ; on C64 */
    s_keymap[MAC_KEY_ANSI_BACKSLASH] = '=';  /* = on C64 */
    s_keymap[MAC_KEY_RETURN]         = VHK_KEY_Return;

    /* Row 4: ZXCV */
    s_keymap[MAC_KEY_LEFTSHIFT]     = X11_KEY_Shift_L;
    s_keymap[MAC_KEY_ANSI_Z]        = 'z';
    s_keymap[MAC_KEY_ANSI_X]        = 'x';
    s_keymap[MAC_KEY_ANSI_C]        = 'c';
    s_keymap[MAC_KEY_ANSI_V]        = 'v';
    s_keymap[MAC_KEY_ANSI_B]        = 'b';
    s_keymap[MAC_KEY_ANSI_N]        = 'n';
    s_keymap[MAC_KEY_ANSI_M]        = 'm';
    s_keymap[MAC_KEY_ANSI_COMMA]    = ',';
    s_keymap[MAC_KEY_ANSI_PERIOD]   = '.';
    s_keymap[MAC_KEY_ANSI_SLASH]    = '/';
    s_keymap[MAC_KEY_RIGHTSHIFT]    = X11_KEY_Shift_R;

    /* Row 5: bottom row */
    s_keymap[MAC_KEY_LEFTCMD]       = X11_KEY_Alt_L;  /* Commodore key → Alt_L */
    s_keymap[MAC_KEY_SPACE]         = VHK_KEY_space;

    /* Cursor keys */
    s_keymap[MAC_KEY_CURSOR_LEFT]   = VHK_KEY_Left;
    s_keymap[MAC_KEY_CURSOR_RIGHT]  = X11_KEY_Right;
    s_keymap[MAC_KEY_CURSOR_UP]     = X11_KEY_Up;
    s_keymap[MAC_KEY_CURSOR_DOWN]   = X11_KEY_Down;

    /* Special */
    s_keymap[MAC_KEY_HOME]          = VHK_KEY_Home;
    s_keymap[MAC_KEY_ESCAPE]        = VHK_KEY_Escape;  /* Run/Stop */
    s_keymap[MAC_KEY_CAPSLOCK]      = X11_KEY_Caps_Lock;
    s_keymap[MAC_KEY_LEFTALT]       = VHK_KEY_F1 + 11; /* F12 → Restore key */
}

/* ── kbd_arch_* — replaces arch/headless/kbd.c ──────────────────────────── */
/*
 * VICE calls kbd_arch_keyname_to_keynum() when parsing a .vkm keymap file to
 * convert GDK/X11 key name strings → numeric keysym values.  The headless
 * arch stub returns -1 for everything, so no keys load.  We provide the full
 * table here (covering every key name in gtk3_sym.vkm + a few extras).
 *
 * Values match X11/GDK keysym definitions.  ASCII printable characters have
 * keysym == ASCII code (0x20–0x7E), so we handle those generically.
 */

typedef struct { const char *name; signed long sym; } keysym_entry_t;

static const keysym_entry_t s_keysym_table[] = {
    /* Control / whitespace */
    { "BackSpace",        0xFF08 },
    { "Tab",              0xFF09 },
    { "ISO_Left_Tab",     0xFE20 },
    { "Return",           0xFF0D },
    { "Escape",           0xFF1B },
    { "space",            0x0020 },
    { "Delete",           0xFFFF },
    /* Cursor / navigation */
    { "Home",             0xFF50 },
    { "Left",             0xFF51 },
    { "Up",               0xFF52 },
    { "Right",            0xFF53 },
    { "Down",             0xFF54 },
    { "Page_Up",          0xFF55 },
    { "Prior",            0xFF55 },
    { "Page_Down",        0xFF56 },
    { "End",              0xFF57 },
    { "Insert",           0xFF63 },
    /* Keypad */
    { "Num_Lock",         0xFF7F },
    { "KP_Enter",         0xFF8D },
    { "KP_F1",            0xFF91 },
    { "KP_F2",            0xFF92 },
    { "KP_F3",            0xFF93 },
    { "KP_F4",            0xFF94 },
    { "KP_Home",          0xFF95 },
    { "KP_Left",          0xFF96 },
    { "KP_Up",            0xFF97 },
    { "KP_Right",         0xFF98 },
    { "KP_Down",          0xFF99 },
    { "KP_Prior",         0xFF9A },
    { "KP_Page_Up",       0xFF9A },
    { "KP_Next",          0xFF9B },
    { "KP_Page_Down",     0xFF9B },
    { "KP_End",           0xFF9F },
    { "KP_Begin",         0xFF9D },
    { "KP_Insert",        0xFF9E },
    { "KP_Delete",        0xFF9F },
    { "KP_Multiply",      0xFFAA },
    { "KP_Add",           0xFFAB },
    { "KP_Subtract",      0xFFAD },
    { "KP_Divide",        0xFFAF },
    { "KP_0",             0xFFB0 },
    { "KP_1",             0xFFB1 },
    { "KP_2",             0xFFB2 },
    { "KP_3",             0xFFB3 },
    { "KP_4",             0xFFB4 },
    { "KP_5",             0xFFB5 },
    { "KP_6",             0xFFB6 },
    { "KP_7",             0xFFB7 },
    { "KP_8",             0xFFB8 },
    { "KP_9",             0xFFB9 },
    /* Function keys */
    { "F1",               0xFFBE },
    { "F2",               0xFFBF },
    { "F3",               0xFFC0 },
    { "F4",               0xFFC1 },
    { "F5",               0xFFC2 },
    { "F6",               0xFFC3 },
    { "F7",               0xFFC4 },
    { "F8",               0xFFC5 },
    { "F9",               0xFFC6 },
    { "F10",              0xFFC7 },
    { "F11",              0xFFC8 },
    { "F12",              0xFFC9 },
    /* Modifier keys */
    { "Shift_L",          0xFFE1 },
    { "Shift_R",          0xFFE2 },
    { "Control_L",        0xFFE3 },
    { "Control_R",        0xFFE4 },
    { "Caps_Lock",        0xFFE5 },
    { "Alt_L",            0xFFE9 },
    { "Alt_R",            0xFFEA },
    { "Meta_L",           0xFFE7 },
    { "Meta_R",           0xFFE8 },
    { "Super_L",          0xFFEB },
    { "Super_R",          0xFFEC },
    /* Misc */
    { "Print",            0xFF61 },
    { "Scroll_Lock",      0xFF14 },
    { "Sys_Req",          0xFF15 },
    { "Pause",            0xFF13 },
    /* Named ASCII symbols (keysym == ASCII value) */
    { "exclam",           0x21 },
    { "quotedbl",         0x22 },
    { "numbersign",       0x23 },
    { "dollar",           0x24 },
    { "percent",          0x25 },
    { "ampersand",        0x26 },
    { "apostrophe",       0x27 },
    { "parenleft",        0x28 },
    { "parenright",       0x29 },
    { "asterisk",         0x2A },
    { "plus",             0x2B },
    { "comma",            0x2C },
    { "minus",            0x2D },
    { "period",           0x2E },
    { "slash",            0x2F },
    { "colon",            0x3A },
    { "semicolon",        0x3B },
    { "less",             0x3C },
    { "equal",            0x3D },
    { "greater",          0x3E },
    { "question",         0x3F },
    { "at",               0x40 },
    { "bracketleft",      0x5B },
    { "backslash",        0x5C },
    { "bracketright",     0x5D },
    { "asciicircum",      0x5E },
    { "underscore",       0x5F },
    { "grave",            0x60 },
    { "bar",              0x7C },
    { "asciitilde",       0x7E },
    /* Latin-1 supplement */
    { "sterling",         0x00A3 },
    /* Dead (combining) keys — used in international layouts */
    { "dead_grave",       0xFE50 },
    { "dead_acute",       0xFE51 },
    { "dead_circumflex",  0xFE52 },
    { "dead_tilde",       0xFE53 },
    { "dead_perispomeni", 0xFE53 },
    { "dead_diaeresis",   0xFE57 },
    { NULL,               0 }
};

int kbd_arch_get_host_mapping(void) {
    return KBD_MAPPING_US;
}

void kbd_arch_init(void)     {}
void kbd_arch_shutdown(void) {}
void kbd_initialize_numpad_joykeys(int *joykeys) { (void)joykeys; }
void kbd_hotkey_init(void)     {}
void kbd_hotkey_shutdown(void) {}

signed long kbd_arch_keyname_to_keynum(char *keyname) {
    if (!keyname || !*keyname) return -1;

    /* Single ASCII printable character — keysym == ASCII code */
    if (keyname[1] == '\0') {
        unsigned char c = (unsigned char)keyname[0];
        if (c >= 0x20 && c <= 0x7E) return (signed long)c;
    }

    /* Named keys: linear scan (table is short) */
    for (const keysym_entry_t *e = s_keysym_table; e->name; e++) {
        if (strcmp(e->name, keyname) == 0) return e->sym;
    }
    return -1;
}

const char *kbd_arch_keynum_to_keyname(signed long keynum) {
    static char buf[16];
    /* Reverse lookup in table */
    for (const keysym_entry_t *e = s_keysym_table; e->name; e++) {
        if (e->sym == keynum) return e->name;
    }
    /* ASCII printable fallback */
    if (keynum >= 0x21 && keynum <= 0x7E) {
        buf[0] = (char)keynum;
        buf[1] = '\0';
        return buf;
    }
    snprintf(buf, sizeof(buf), "%ld", (long)keynum);
    return buf;
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

    /* Translate NSEvent modifier flags to VICE KBD_MOD_* bitmask.
     * NSEventModifierFlagShift   = 1<<17 (0x20000)
     * NSEventModifierFlagControl = 1<<18 (0x40000)
     * NSEventModifierFlagOption  = 1<<19 (0x80000)  — Alt/Commodore key
     * macOS does not distinguish L/R shift in the flags; we track those
     * via the individual key-press events (Shift_L / Shift_R) instead. */
    int viceMod = 0;
    if (modifiers & (1u << 17)) viceMod |= KBD_MOD_LSHIFT;
    if (modifiers & (1u << 18)) viceMod |= KBD_MOD_LCTRL;
    if (modifiers & (1u << 19)) viceMod |= KBD_MOD_LALT;

    if (down) {
        keyboard_key_pressed((signed long)viceKey, viceMod);
    } else {
        keyboard_key_released((signed long)viceKey, viceMod);
    }
}

void vice_mac_modifier_event(uint16_t macKeyCode, uint32_t modifiers) {
    /* NSEventTypeFlagsChanged fires for modifier key press AND release.
     * Determine press vs release by checking the modifier flag bit for this
     * key against the current modifierFlags value.
     *
     * NSEventModifierFlagShift   = 1<<17 = 0x00020000
     * NSEventModifierFlagControl = 1<<18 = 0x00040000
     * NSEventModifierFlagOption  = 1<<19 = 0x00080000
     * NSEventModifierFlagCommand = 1<<20 = 0x00100000
     * NSEventModifierFlagCapsLock= 1<<16 = 0x00010000
     */
    static const struct {
        uint16_t keyCode;
        uint32_t flagBit;
    } modMap[] = {
        { MAC_KEY_LEFTSHIFT,  1u << 17 },
        { MAC_KEY_RIGHTSHIFT, 1u << 17 },
        { MAC_KEY_LEFTCTRL,   1u << 18 },
        { MAC_KEY_LEFTALT,    1u << 19 },
        { MAC_KEY_LEFTCMD,    1u << 20 },
        { MAC_KEY_CAPSLOCK,   1u << 16 },
        { 0, 0 }
    };

    uint32_t flagBit = 0;
    for (int i = 0; modMap[i].keyCode != 0; i++) {
        if (modMap[i].keyCode == macKeyCode) {
            flagBit = modMap[i].flagBit;
            break;
        }
    }

    int down = (flagBit != 0) ? ((modifiers & flagBit) != 0) : 0;
    vice_mac_key_event(macKeyCode, modifiers, down);
}
