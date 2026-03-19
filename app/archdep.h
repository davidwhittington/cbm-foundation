/* archdep.h — c=foundation macOS arch-specific definitions
 * Adapted from vice/src/arch/headless/archdep.h.
 * Included by VICE core files via #include "archdep.h".
 */

#ifndef VICE_ARCHDEP_H
#define VICE_ARCHDEP_H

/* NOTE: do NOT include <stdbool.h> here — causes bugs in monitor code */
#include "vice.h"
#include "sound.h"

/* Video chip scaling defaults */
#define ARCHDEP_VICII_DSIZE   1
#define ARCHDEP_VICII_DSCAN   1
#define ARCHDEP_VDC_DSIZE     1
#define ARCHDEP_VDC_DSCAN     1
#define ARCHDEP_VIC_DSIZE     1
#define ARCHDEP_VIC_DSCAN     1
#define ARCHDEP_CRTC_DSIZE    1
#define ARCHDEP_CRTC_DSCAN    1
#define ARCHDEP_TED_DSIZE     1
#define ARCHDEP_TED_DSCAN     1

/* Keyboard */
#define ARCHDEP_KEYBOARD_SYM_NONE 0

/* Sound */
#define ARCHDEP_SOUND_OUTPUT_MODE SOUND_OUTPUT_SYSTEM

/* Separate monitor window */
#define ARCHDEP_SEPERATE_MONITOR_WINDOW

/* Mouse grab default */
#define ARCHDEP_MOUSE_ENABLE_DEFAULT    0

/* Status bar factory default */
#define ARCHDEP_SHOW_STATUSBAR_FACTORY  0

/* Pull in Unix shared archdep */
#ifdef UNIX_COMPILE
#include "archdep_unix.h"
#endif

/* Prototype for our archdep_get_vice_datadir override (implemented in vice_mac_sdl.c) */
char *archdep_get_vice_datadir(void);
char *archdep_get_vice_docsdir(void);

int  archdep_register_cbmfont(void);
void archdep_unregister_cbmfont(void);
void archdep_user_config_path_free(void);

#endif /* VICE_ARCHDEP_H */
