/* vice_mac_joystick.h
 * GameController joystick integration for c=foundation.
 *
 * Connects physical and MFi controllers to VICE's joystick ports.
 * Controller 0 → Port 2 (the default for most C64 games).
 * Controller 1 → Port 1 (player 2 / second fire button).
 *
 * Threading: GCController callbacks update atomic state; vice_mac_joystick_poll()
 * is called on the VICE thread from vsyncarch_presync() to apply the state.
 */

#ifndef VICE_MAC_JOYSTICK_H
#define VICE_MAC_JOYSTICK_H

/**
 * Initialise the joystick subsystem.
 * Registers GameController connect/disconnect observers and sets up
 * input handlers for any already-connected controllers.
 * Call once from the main thread during app startup.
 */
void vice_mac_joystick_init(void);

/**
 * Poll current joystick state and push it to VICE.
 * Must be called on the VICE emulation thread (from vsyncarch_presync).
 * Reads atomic state written by GameController callbacks and calls
 * joystick_set_value_absolute() for ports 1 and 2.
 */
void vice_mac_joystick_poll(void);

/**
 * Swap joystick ports.
 * When swapped=1, the first connected controller maps to port 1 instead of
 * port 2 (the default).  Changes take effect on the next poll cycle.
 */
void vice_mac_joystick_set_port_swap(int swapped);

/**
 * Shut down the joystick subsystem.
 * Removes observers and clears all port state.
 */
void vice_mac_joystick_shutdown(void);

#endif /* VICE_MAC_JOYSTICK_H */
