// resid-config.h — c=foundation override
// Ensures config.h (vice_config.h) is included before siddefs.h processes VERSION.
// This file is found first in the header search path, overriding vice/src/resid/resid-config.h.

#ifndef RESID_CONFIG_H
#define RESID_CONFIG_H

// Include our vice_config.h (via config.h symlink) to get VERSION defined
#include "config.h"

// Include the real siddefs.h from the resid directory
#include "siddefs.h"

#endif
