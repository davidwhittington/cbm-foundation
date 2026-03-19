/* vice_mac_kbd.h
 * NSEvent keyboard input → VICE C64 keyboard matrix translation.
 */

#ifndef VICE_MAC_KBD_H
#define VICE_MAC_KBD_H

#include <stdint.h>

/**
 * Initialise the keyboard subsystem.
 * Loads the appropriate .vkm keymap file (positional by default).
 */
void vice_mac_kbd_init(void);

/**
 * Deliver a key event from the macOS event loop to the VICE keyboard matrix.
 * Call from the main thread (from vice_mac_process_pending_events).
 *
 * @param macKeyCode   NSEvent.keyCode (hardware scan code, layout-independent)
 * @param modifiers    NSEvent.modifierFlags
 * @param down         YES = key pressed, NO = key released
 */
void vice_mac_key_event(uint16_t macKeyCode, uint32_t modifiers, int down);

/**
 * Deliver a modifier-key FlagsChanged event to VICE.
 * Determines press vs release by checking whether the modifier flag
 * corresponding to macKeyCode is set in the current modifiers bitmask.
 */
void vice_mac_modifier_event(uint16_t macKeyCode, uint32_t modifiers);

#endif /* VICE_MAC_KBD_H */
