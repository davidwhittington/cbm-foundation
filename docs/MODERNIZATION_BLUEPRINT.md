# cbm-foundation — Modernization Blueprint
## Native macOS App Suite for Commodore Emulation via VICE

**C core repo:** `vice-emu-code` (https://github.com/davidwhittington/vice-emu-code)
**Base emulator:** VICE 3.9 (GPLv2)
**Reference pattern:** fuji-foundation / Atari800MacX
**Date:** March 2026

---

## The CBM Suite

Four apps, one C core:

| App | Platform | Scope |
|-----|----------|-------|
| **cbm-foundation** | macOS 14+ | 1:1 VICE port — full feature set, all machines |
| **cbm-swift** | macOS 14+ | Stripped down — C64 only, minimal UI, fast |
| **cbm-vision** | visionOS 2+ | Spatial — 3D bezel, mixed reality retro computing |
| **cbm-dynasty** | macOS 14+ | Everything — all add-ons, net2iec, Meatloaf, physical drives |

All four apps compile the same VICE C core unchanged. They differ only in the Swift/SwiftUI/Metal layer above it.

**GitHub repos:**
- https://github.com/davidwhittington/cbm-foundation
- https://github.com/davidwhittington/cbm-swift
- https://github.com/davidwhittington/cbm-vision
- https://github.com/davidwhittington/cbm-dynasty

---

## Implementation Status — cbm-foundation

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Xcode project setup and VICE core extraction | Scaffolded |
| 2 | macOS arch layer (vice_mac_sdl.c) | Scaffolded |
| 3 | Metal rendering pipeline | Scaffolded |
| 4 | VICEEngine ObjC bridge | Scaffolded |
| 5 | SwiftUI preference panels + machine selector | Scaffolded |
| 6 | NetIEC protocol scaffold | Scaffold only |
| 7 | net2iec — Meatloaf integration | Planned |
| 8 | Physical Commodore drive support | Planned |
| 9 | FujiNet-PC integration | Stubbed |
| 10 | Code signing and notarization | Planned |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      cbm-foundation.app                          │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │               Swift / AppKit GUI Layer                     │  │
│  │                                                            │  │
│  │  ┌─────────────┐  ┌──────────────┐  ┌──────────────────┐  │  │
│  │  │ Main Window  │  │ Preferences  │  │ Machine Selector  │  │  │
│  │  │ (AppKit+MTK) │  │  (SwiftUI)   │  │    (SwiftUI)     │  │  │
│  │  └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘  │  │
│  │         │                 │                   │            │  │
│  │  ┌──────▼─────────────────▼───────────────────▼─────────┐  │  │
│  │  │           Swift / ObjC Bridge Layer                   │  │  │
│  │  │  VICEEngine | VICEDisplayManager | MediaBridge        │  │  │
│  │  └────────────────────────┬──────────────────────────────┘  │  │
│  └───────────────────────────┼──────────────────────────────┘  │
│                              │                                   │
│  ┌───────────────────────────▼─────────────────────────────┐    │
│  │         VICE C Core (Untouched, vice-emu-code/src/*)     │    │
│  │  maincpu.c | c64/*.c | vicii/*.c | sid/*.c | iecbus.c   │    │
│  └──────────────────────────────────────────────────────────┘    │
│                                                                   │
│  ┌──────────────────────┐  ┌────────────────────────────────┐    │
│  │  VICEMetalView       │  │  vice_mac_sdl.c (arch layer)   │    │
│  │  (MTKView + shaders) │  │  SDL2: input + audio bridge    │    │
│  └──────────────────────┘  └────────────────────────────────┘    │
│                                                                   │
│  ┌──────────────────────┐  ┌────────────────────────────────┐    │
│  │  net2iec.c/.h        │  │  physdrv.c/.h                  │    │
│  │  Meatloaf UDP bridge │  │  OpenCBM / XUM1541 / ZoomFloppy│    │
│  │  IEC virtual devices │  │  USB-connected real drives     │    │
│  └──────────────────────┘  └────────────────────────────────┘    │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │  netiec.c/.h — FujiNet-PC UDP bridge (IEC units 8–11)     │   │
│  └────────────────────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────────────┘
```

---

## Directory Layout

```
cbm-foundation/
├── apps/
│   └── cbm-foundation-app/              ← macOS app layer
│       ├── CFoundationApp.swift         ← Swift entry point
│       ├── main.c                       ← C entry point → main_program()
│       ├── vice_mac_sdl.c/.h            ← macOS arch layer
│       ├── vice_mac_vsync.c/.h          ← vsyncarch_* implementations
│       ├── vice_mac_ui.c/.h             ← ui_* implementations (uiapi.h contract)
│       ├── vice_mac_kbd.c/.h            ← NSEvent key codes → VICE key translation
│       ├── vice_mac_joy.c/.h            ← GameController.framework → VICE joystick
│       ├── vice_mac_sound.c             ← selects CoreAudio driver
│       ├── VICEMetalView.h/.m           ← MTKView subclass, Metal pipeline
│       ├── VICEDisplayManager.h/.m      ← frame buffer → Metal texture
│       ├── VICEEngine.h/.m              ← ObjC bridge to VICE C core
│       ├── PreferenceModel.swift        ← @Observable SwiftUI data model
│       ├── MachineModel.swift           ← enum: C64, C128, VIC20, PET, Plus4
│       ├── SwiftUIPanelCoordinator.swift
│       ├── PreferencesView.swift        ← SwiftUI tab-based preferences panel
│       ├── MachineSelector.swift        ← machine picker SwiftUI view
│       ├── MediaManagerView.swift       ← disk/tape/cartridge attach panel
│       ├── DriveManagerView.swift       ← physical + virtual drive panel
│       ├── Shaders.metal                ← fullscreen quad + CRT effects
│       ├── net2iec.c/.h                 ← net2iec / Meatloaf bridge
│       ├── netiec.c/.h                  ← NetIEC / FujiNet-PC bridge
│       ├── physdrv.c/.h                 ← physical Commodore drive support
│       ├── vice_config.h                ← hand-maintained config.h for Xcode
│       └── Resources/
│           ├── cbm-foundation.icns
│           ├── COPYING                  ← GPL v2 text
│           └── vice-data/               ← ROMs + keymaps (sync_vice_data.sh)
├── vice/                                ← symlink or submodule → vice-emu-code
│   └── src/
├── scripts/
│   ├── build_release.sh
│   └── sync_vice_data.sh
├── docs/
│   ├── MODERNIZATION_BLUEPRINT.md       ← this file
│   └── CBM_SUITE_OVERVIEW.md
├── .gitignore
└── README.md
```

---

## Phase 1 — Xcode Project Setup and VICE Core Extraction

**Goal:** A compiling Xcode project including the VICE C core.
**Risk:** Medium. VICE uses autoconf; we bypass it and compile sources directly in Xcode.

### 1.1 Xcode Target

- Single app target: `CFoundationMacX`
- macOS 14.0 deployment target
- `SWIFT_VERSION = 5.9`
- `CLANG_ENABLE_OBJC_ARC = YES`
- `GCC_ENABLE_CPP_EXCEPTIONS = NO` (VICE core is pure C; ReSID is C++)

### 1.2 xcconfig Settings

```xcconfig
MACOSX_DEPLOYMENT_TARGET = 14.0
SWIFT_VERSION = 5.9
CLANG_ENABLE_OBJC_ARC = YES
ENABLE_HARDENED_RUNTIME = YES

HEADER_SEARCH_PATHS = $(inherited) \
    $(SRCROOT)/vice/src \
    $(SRCROOT)/vice/src/arch/shared \
    $(SRCROOT)/vice/src/c64 \
    $(SRCROOT)/vice/src/vicii \
    $(SRCROOT)/vice/src/sid \
    $(SRCROOT)/vice/src/drive \
    $(SRCROOT)/vice/src/iecbus \
    $(SRCROOT)/vice/src/video \
    $(SRCROOT)/vice/src/core \
    $(SRCROOT)/vice/src/raster \
    $(SRCROOT)/apps/cbm-foundation-app

GCC_PREPROCESSOR_DEFINITIONS = $(inherited) \
    MACOSX USE_COREAUDIO USE_VICE_THREAD VICE_ARCHTYPE_NATIVE_MACOS
```

### 1.3 VICE Source File Scope (Phase 1: C64 only)

Compile directly from `vice/src/`:
- **Core:** `main.c`, `maincpu.c`, `mainlock.c`, `machine.c`, `machine-bus.c`, `init.c`
- **C64 machine:** all `c64/*.c` except `c64dtv*` and `vsid*`
- **Video:** `video/*.c`, `vicii/*.c`, `raster/*.c`
- **SID:** `sid/*.c`, `resid/*.cc` (C++ — compile as ObjC++ or separate static lib)
- **Drive:** `drive/*.c`
- **Serial/IEC:** `iecbus/iecbus.c`, `serial/*.c`
- **Sound:** `sound.c`, `arch/shared/sounddrv/soundcoreaudio.c`
- **Arch/shared:** `arch/shared/archdep_*.c`, `arch/shared/macOS-util.m`
- **Utilities:** `lib.c`, `log.c`, `util.c`, `resources.c`, `cmdline.c`, `vsync.c`

**Excluded:** everything under `vice/src/arch/sdl/` and `vice/src/arch/gtk3/`.
Our `apps/cbm-foundation-app/vice_mac_*.c` files replace them entirely.

### 1.4 vice_config.h

VICE's `config.h` is normally autoconf-generated. For Xcode, maintain `apps/cbm-foundation-app/vice_config.h` by hand. Bootstrap from a successful configure run:

```bash
cd vice && ./configure --enable-native-tools --without-gtk3 --with-sdl2
# Use the generated config.h as the base for vice_config.h
```

### 1.5 ROM Data

Build phase copies `vice/src/data/C64/` into `Resources/vice-data/C64/`.

Override `archdep_get_vice_datadir()` in `vice_mac_sdl.c`:
```c
char *archdep_get_vice_datadir(void) {
    CFURLRef url = CFBundleCopyResourcesDirectoryURL(CFBundleGetMainBundle());
    char path[PATH_MAX];
    CFURLGetFileSystemRepresentation(url, true, (uint8_t *)path, PATH_MAX);
    CFRelease(url);
    char *result = lib_malloc(strlen(path) + strlen("/vice-data") + 1);
    sprintf(result, "%s/vice-data", path);
    return result;
}
```

---

## Phase 2 — macOS Arch Layer

**Goal:** Replace `vice/src/arch/sdl/` with native macOS implementations.
**Risk:** High. Every function in `uiapi.h` must be implemented; missing stubs fail to link.

### Key Files

- `vice_mac_sdl.c` — central arch file: `archdep_init()`, `video_canvas_create()`, `video_canvas_refresh()`
- `vice_mac_ui.c` — implements every function in `src/uiapi.h`
- `vice_mac_vsync.c` — `vsyncarch_presync/postsync`, minimal (USE_VICE_THREAD handles timing)
- `vice_mac_kbd.c` — NSEvent key codes → VICE key matrix via `keyboard_key_pressed()`
- `vice_mac_joy.c` — `GCController` → `joystick_set_value_absolute()`
- `vice_mac_sound.c` — sets sound driver to `"coreaudio"`, reuses `soundcoreaudio.c` unchanged

### Threading Model

With `USE_VICE_THREAD`:
- `main_program()` spawns VICE thread and returns immediately
- VICE thread runs `maincpu_mainloop()` forever
- UI calls into VICE **must** wrap with `mainlock_obtain()` / `mainlock_release()`
- `vsyncarch_presync()` calls `mainlock_yield()` to give main thread lock access

---

## Phase 3 — Metal Rendering Pipeline

**Goal:** MTKView-based renderer replacing SDL display output.

### C64 Frame Buffer

- Resolution: 384×272 (full frame with borders)
- Format: ARGB8888 (32-bit) after VICE's palette conversion
- Pixel aspect: approximately 0.9375 (PAL) or 1.0 (NTSC)

### VICEMetalView

Mirrors `EmulatorMetalView.h/.m` from fuji-foundation exactly.
Key properties: `scanlinesEnabled`, `crtCurvatureEnabled`, `brightness`, `saturation`, `contrast`.

`presentFrame:` called from `VICEDisplayManager` after each `video_canvas_refresh()`.

### VICEDisplayManager

Lock-free double-buffer between VICE thread and Metal render thread.
Uses `os_unfair_lock` for minimal contention.

### Shaders.metal

Fullscreen quad with:
- Nearest-neighbor or bilinear texture sampling
- Optional scanline darkening (every other row × 0.72)
- Optional CRT barrel distortion
- Per-frame brightness / saturation / contrast controls
- Liquid Glass panel overlays on visionOS (cbm-vision only)

---

## Phase 4 — VICEEngine ObjC Bridge

**Goal:** Single ObjC class owning the VICE lifecycle; the only C↔Swift interface.

### Key API Surface

```objc
@interface VICEEngine : NSObject
+ (instancetype)sharedEngine;

// Lifecycle
- (BOOL)startWithMachine:(VICEMachineModel)machine error:(NSError **)error;
- (void)stop;
- (void)reset:(VICEResetMode)mode;

// Media (wraps mainlock internally)
- (BOOL)attachDiskURL:(NSURL *)url unit:(NSInteger)unit drive:(NSInteger)drive error:(NSError **)error;
- (void)detachDiskFromUnit:(NSInteger)unit drive:(NSInteger)drive;
- (BOOL)attachTapeURL:(NSURL *)url error:(NSError **)error;
- (BOOL)attachCartridgeURL:(NSURL *)url error:(NSError **)error;

// Snapshots
- (BOOL)saveSnapshotToURL:(NSURL *)url error:(NSError **)error;
- (BOOL)loadSnapshotFromURL:(NSURL *)url error:(NSError **)error;

// Input
- (void)keyDown:(uint16_t)macKeyCode modifiers:(NSEventModifierFlags)mods;
- (void)keyUp:(uint16_t)macKeyCode modifiers:(NSEventModifierFlags)mods;
- (void)joystickPort:(NSInteger)port direction:(uint8_t)dir fire:(BOOL)fire;

@property (nonatomic) BOOL warpEnabled;
@property (nonatomic) BOOL pauseEnabled;
@end
```

---

## Phase 5 — SwiftUI Panels

**Goal:** Preferences + machine selector in SwiftUI, bridged via NSHostingController.

### Preference Tabs
1. **Machine** — model (C64/C128/VIC-20/PET/Plus4), RAM config, kernal ROM
2. **Video** — scanlines, CRT curve, brightness, saturation, contrast, scaling mode
3. **Audio** — SID model (6581 vs 8580), volume, stereo
4. **Drives** — true drive emulation on/off, virtual devices, drive sounds
5. **Input** — joystick port assignments, keyboard map selection
6. **Network** — NetIEC enable/disable, net2iec/Meatloaf host:port, FujiNet-PC host:port

### Machine Switching

Switching machines requires an app restart in Phase 5 (VICE is a single-machine-class binary).
Store selection in `UserDefaults`; read at startup. Full in-process switching is Phase 9+.

---

## Phase 6 — NetIEC Protocol Scaffold (FujiNet-PC)

**Goal:** Define the NetIEC interface; implement UDP transport for FujiNet-PC connectivity.

### Why NetIEC != NetSIO

| Dimension | Atari SIO (NetSIO) | Commodore IEC (NetIEC) |
|-----------|-------------------|----------------------|
| Bus type | Star, byte-serial | Multi-drop, bit-serial |
| Lines | DATA, CMD, MOTOR | ATN, CLK, DATA, RESET |
| VICE hook | `sio_callback` | `iecbus_callback_read/write` |
| Speed | ~19200 baud | ~1000 baud (standard) |

### Intercept Strategy

Register a virtual IEC device for units 8–11 via `serial_t` callbacks.
Relay open/close/get/put to FujiNet-PC over UDP on default port **6400**.

### NetIEC Message IDs

```c
#define NETIEC_ATN_ASSERT        0x10
#define NETIEC_ATN_RELEASE       0x11
#define NETIEC_CLK_ASSERT        0x12
#define NETIEC_CLK_RELEASE       0x13
#define NETIEC_DATA_ASSERT       0x14
#define NETIEC_DATA_RELEASE      0x15
#define NETIEC_BYTE_TO_DEVICE    0x20
#define NETIEC_BYTE_FROM_DEVICE  0x21
#define NETIEC_EOI               0x22
#define NETIEC_BLOCK_TO_DEVICE   0x28
#define NETIEC_BLOCK_FROM_DEVICE 0x29
#define NETIEC_DEVICE_CONNECTED    0xC1
#define NETIEC_DEVICE_DISCONNECTED 0xC0
#define NETIEC_PING_REQUEST        0xC2
#define NETIEC_PING_RESPONSE       0xC3
#define NETIEC_ALIVE_REQUEST       0xC4
#define NETIEC_ALIVE_RESPONSE      0xC5
#define NETIEC_WARM_RESET          0xFE
#define NETIEC_COLD_RESET          0xFF
```

---

## Phase 7 — net2iec: Meatloaf Integration

**Goal:** Connect cbm-dynasty and cbm-foundation to Meatloaf network drive servers
over IEC, allowing the emulated C64 to browse and load from Meatloaf endpoints.

### What Meatloaf Is

Meatloaf is a Commodore IEC serial multi-device emulator running on ESP32 hardware.
It exposes Commodore drives (units 8–15) over WiFi, presenting network filesystems,
HTTP endpoints, BBS systems, and cloud storage as mountable IEC devices. Think of it
as a FujiNet for the Commodore side.

Repo: https://github.com/idolpx/meatloaf

### net2iec Architecture

```
cbm-foundation (macOS)
  → net2iec.c (virtual IEC device, units 8–11)
    → UDP or WebSocket to Meatloaf server (ESP32 on network)
      → Meatloaf: HTTP/BBS/CBM filesystem backends
```

net2iec mirrors the netiec.c pattern but targets Meatloaf's protocol rather than
FujiNet-PC's NetIEC. The two protocols are distinct and may be assigned separate
unit ranges (e.g., net2iec owns units 9–11, netiec owns unit 8).

### net2iec Protocol (Meatloaf)

Meatloaf exposes a virtual IEC bus over TCP/WebSocket. The protocol mirrors
IEC electrical signals as message frames:

```c
// net2iec message types (Meatloaf TCP protocol)
#define NET2IEC_OPEN    0x01   // OPEN secondary address, filename
#define NET2IEC_CLOSE   0x02   // CLOSE secondary address
#define NET2IEC_TALK    0x03   // TALK (host reads from device)
#define NET2IEC_LISTEN  0x04   // LISTEN (host writes to device)
#define NET2IEC_UNLISTEN 0x05
#define NET2IEC_UNTALK   0x06
#define NET2IEC_DATA    0x10   // data payload
#define NET2IEC_EOI     0x11   // end-of-indicator
#define NET2IEC_STATUS  0x12   // request error channel (status)
```

Default: TCP to Meatloaf host:port (configurable, default `meatloaf.local:1541`).

### Intercept Point in VICE

Same serial_t callback registration as netiec. net2iec registers for units 9–11:
```c
serial_device_type_set(SERIAL_DEVICE_NET2IEC, 9);
serial_device_type_set(SERIAL_DEVICE_NET2IEC, 10);
serial_device_type_set(SERIAL_DEVICE_NET2IEC, 11);
```

### cbm-dynasty vs cbm-foundation

- **cbm-foundation**: net2iec scaffolded, disabled by default, enabled in Network prefs
- **cbm-dynasty**: net2iec enabled by default, auto-discovery of Meatloaf devices on LAN

---

## Phase 8 — Physical Commodore Drive Support

**Goal:** Connect real Commodore disk drives (1541, 1571, 1581) to the emulated C64 via
USB adapters, using the emulated IEC bus to route data between the C64 and the physical drive.

### Hardware Adapters

| Adapter | Interface | Library | Notes |
|---------|-----------|---------|-------|
| ZoomFloppy | USB | opencbm | Open source, widely available |
| XUM1541 | USB | opencbm | ZoomFloppy reference design |
| 1541 Ultimate II | USB | opencbm | cartridge + drive in one |
| Raspberry Pi GPIO | GPIO | cbm-pi | Direct bit-bang via GPIO (Pi only) |

### opencbm Integration

VICE includes partial opencbm support in `src/arch/shared/` for IEC pass-through.
The macOS arch layer needs to wire the `opencbm` library to VICE's IEC bus.

Prerequisites:
- opencbm macOS build (requires libusb-1.0 via Homebrew)
- ZoomFloppy or XUM1541 USB adapter connected

```c
// physdrv.c — physical drive intercept
#ifdef HAVE_OPENCBM
#include <opencbm.h>

static CBM_FILE phys_cbm_fd;

int physdrv_open(void) {
    return cbm_driver_open_ex(&phys_cbm_fd, NULL);
}

void physdrv_close(void) {
    cbm_driver_close(phys_cbm_fd);
}

// Register as VICE real-drive device for unit 8 (or user-configured unit)
void physdrv_register_unit(int unit) {
    serial_device_type_set(SERIAL_DEVICE_PHYSICAL, unit);
}
#endif
```

### UI Integration

**DriveManagerView** (SwiftUI) shows:
- Connected physical drives (via IOKit USB detection)
- Per-unit assignment: emulated / virtual / net2iec / physical / netiec
- Drive model identification (reads 1541/1571/1581 from device string)
- Activity indicator (IEC CLK/DATA line state)

### Build Conditions

Physical drive support is optional and gated:
```
HAVE_OPENCBM = 1  (set in vice_config.h when opencbm is present)
```

cbm-dynasty ships with opencbm bundled; cbm-foundation makes it optional at build time.

---

## Phase 9 — FujiNet-PC Integration

**Status:** Stubbed pending FujiNet-PC IEC server availability.

FujiNet-PC today fully supports Atari SIO via NetSIO. Commodore IEC support is in active
development. When FujiNet-PC's NetIEC listener is available, wire it to `netiec.c`.

Target: `localhost:6400` UDP, configurable in Network preferences.

---

## Phase 10 — Code Signing and Notarization

### Entitlements Required

```xml
<key>com.apple.security.files.user-selected.read-write</key><true/>
<key>com.apple.security.files.downloads.read-write</key><true/>
<key>com.apple.security.device.usb</key><true/>
<key>com.apple.security.device.bluetooth</key><true/>
<key>com.apple.security.network.client</key><true/>
<key>com.apple.security.cs.disable-library-validation</key><true/>
```

### GPL Compliance

VICE is GPLv2. Distribution requires:
- `Resources/COPYING` — full GPL v2 text
- Source link in About box and README
- Attribution notice in About box

---

## CBM Suite Differentiation

### cbm-swift (Minimal)
- C64 only (no machine selector)
- Basic Metal CRT display
- No monitor/debugger
- No netiec/net2iec/physical drives
- Smallest binary, fastest startup
- Target: casual users

### cbm-foundation (Full Port)
- All VICE machines: C64, C128, VIC-20, PET, Plus4
- Full preferences: video, audio, drives, input
- Monitor/debugger (VICE's built-in)
- netiec scaffold + net2iec (disabled by default)
- Physical drive support (optional, requires opencbm)
- Target: serious users, developers

### cbm-vision (visionOS)
- C64 + C128 + VIC-20
- 3D bezel with Liquid Glass panels
- Spatial audio (SID in 3D space)
- Hand tracking → virtual keyboard
- Passthrough mode: virtual C64 on real desk
- No physical drive support (no USB in visionOS)
- Target: spatial computing showcase

### cbm-dynasty (Everything)
- All machines + all peripherals
- net2iec enabled by default, Meatloaf auto-discovery
- Physical drive support (opencbm bundled)
- FujiNet-PC integration when available
- Plugin architecture for future hardware
- JiffyDOS speed negotiation
- CBM command-line tools (c1541, petcat) bundled
- Target: power users, hardware collectors

---

## VICE Threading Reference

```
Main Thread                       VICE Thread (vice_thread_main)
─────────────────                 ──────────────────────────────
main_program()
  → init resources, video, ui
  → pthread_create(vice_thread)   starts main_loop_forever()
  → returns 0                         → maincpu_mainloop() (infinite)

AppKit runloop active
  → MTKView calls drawInMTKView   video_canvas_refresh() runs on VICE thread
  → user input events             feeds through vice_mac_kbd/joy.c

To call VICE C APIs from main thread:
  mainlock_obtain();              VICE yields at vsyncarch_presync
  file_system_attach_disk(...);
  mainlock_release();
```

---

## Mapping fuji-foundation → cbm-foundation

| fuji-foundation | cbm-foundation | Notes |
|----------------|---------------|-------|
| `Atari800Engine.h/.m` | `VICEEngine.h/.m` | VICE mainlock replaces custom locking |
| `EmulatorMetalView.h/.m` | `VICEMetalView.h/.m` | 384×272 vs 336×240 |
| `atari_mac_sdl.c` | `vice_mac_sdl.c` | Replaces `vice/src/arch/sdl/` entirely |
| `PreferenceModel.swift` | `PreferenceModel.swift` | Adds SID model, drive ROMs |
| `netsio.c/.h` | `netiec.c/.h` | Different protocol; not a clone |
| `SwiftUIPanelCoordinator.swift` | `SwiftUIPanelCoordinator.swift` | Identical pattern |
| N/A | `net2iec.c/.h` | Meatloaf-specific; no Atari equivalent |
| N/A | `physdrv.c/.h` | Physical drive via opencbm |

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `vice_config.h` missing defines | High | High | Run `./configure` on macOS first |
| ReSID C++ mixing with ObjC | Medium | Medium | Compile resid as separate static lib |
| `video_canvas_refresh` pixel format mismatch | Medium | High | Byte-swap pass in VICEDisplayManager |
| mainlock deadlock | Medium | High | Thread Sanitizer in Debug |
| net2iec protocol diverges from Meatloaf | Medium | Medium | Keep versioned; coordinate with idolpx |
| opencbm macOS build complexity | High | Medium | Bundle prebuilt xcframework in cbm-dynasty |
| Machine switching requires restart | High | Low | Document clearly; Phase 9+ enhancement |
| GPL compliance | Low | High | Ship COPYING, link sources in About box |
