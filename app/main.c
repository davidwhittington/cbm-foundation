/* main.c — c=foundation entry point
 * Thin wrapper that calls VICE's main_program().
 * The VICE thread is spawned inside main_program() when USE_VICE_THREAD is defined.
 * After main_program() returns, we hand off to the AppKit runloop.
 */

#include "vice_config.h"
#include "main.h"
#include <stdio.h>

int main(int argc, char *argv[]) {
    /* main_program() initialises all VICE subsystems, spawns the VICE thread,
     * then returns 0. The AppKit runloop (started by NSApplicationMain in the
     * ObjC AppDelegate) drives the rest of the app lifetime. */
    return main_program(argc, argv);
}
