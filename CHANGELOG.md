# Changelog — cbm-foundation / VICE

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Added — Initial scaffold: cbm-foundation macOS emulator app

**Project scope defined:** cbm-foundation is the 1:1 macOS port of VICE 3.9 for Commodore
hardware, modeled on the fuji-foundation / Atari800MacX pattern. It is the foundation app in
the cbm-* suite (cbm-foundation, cbm-swift, cbm-vision, cbm-dynasty).

**`apps/cfoundation-app/` — macOS app layer (Phase 1–5 scaffold):**

- `CFoundationApp.swift` — minimal Swift entry point, AppKit app lifecycle
- `main.c` — C entry point calling `main_program()` (VICE core init)
- `vice_mac_sdl.c/.h` — macOS arch layer replacing `vice/src/arch/sdl/` entirely;
  implements `archdep_init()`, `video_canvas_create()`, `video_canvas_refresh()`
- `vice_mac_kbd.c/.h` — NSEvent key codes to VICE key matrix translation via
  `keyboard_key_pressed()` / `keyboard_key_released()`
- `VICEMetalView.h/.m` — MTKView subclass owning the Metal render pipeline;
  `presentFrame:` called from VICEDisplayManager after each emulator frame
- `VICEDisplayManager.h/.m` — lock-free double-buffer between VICE thread and
  Metal render thread using `os_unfair_lock`
- `VICEEngine.h/.m` — ObjC bridge to VICE C core; single class owning the VICE
  lifecycle; all C API calls wrap `mainlock_obtain/release`
- `Shaders.metal` — fullscreen quad shader with scanline darkening, CRT barrel
  distortion, and per-frame brightness/saturation/contrast controls
- `PreferenceModel.swift` — `@Observable` SwiftUI data model for all emulator settings
- `MachineSelector.swift` — SwiftUI machine picker (C64, C128, VIC-20, PET, Plus4)
- `MediaManagerView.swift` — disk/tape/cartridge attach panel
- `PreferencesView.swift` — 6-tab SwiftUI preferences: Machine, Video, Audio,
  Drives, Input, Network
- `SwiftUIPanelCoordinator.swift` — NSHostingController bridge from ObjC to SwiftUI
- `netiec.c/.h` — NetIEC protocol scaffold for FujiNet-PC integration;
  registers virtual IEC devices for units 8–11; UDP transport on port 6400
- `vice_config.h` — hand-maintained Xcode-compatible substitute for autoconf config.h;
  bootstrapped from `./configure --without-gtk3 --with-sdl2` on macOS
- `archdep.h` — macOS arch dependency header
- `resid-config.h` — reSID compile-time configuration
- `CFoundationMacX-Bridging-Header.h` — Swift/ObjC bridging header
- `CFoundationMacX.entitlements` — app sandbox entitlements

**`CFoundationMacX.xcodeproj` / `project.yml` (XcodeGen):**

- Single app target `CFoundationMacX`, macOS 14.0, Swift 5.9
- VICE 3.9 C core compiled directly from `vice/vice-3.9/src/` — no autoconf,
  no SDL dependency; arch/sdl entirely replaced by our macOS layer
- Frameworks: MetalKit, Metal, GameController, AVFoundation, CoreAudio,
  AudioUnit, AudioToolbox, CoreVideo, AppKit
- `HAVE_CONFIG_H=1` — VICE source files self-include our `vice_config.h`
- Preprocessor: `MACOSX=1`, `UNIX_COMPILE=1`, `USE_VICE_THREAD=1`,
  `VICE_ARCHTYPE_NATIVE_MACOS=1`, `HAVE_AUDIO_UNIT=1`
- Explicit VICE source directory includes covering: c64, c64/cart, video, vicii,
  raster, sid, resid, drive, iecbus, serial, tape, tapeport, joyport, core,
  core/rtc, diskimage, vdrive, datasette, imagecontents, fileio, parallel,
  userport, rs232drv, monitor, viciisc, vdc, printerdrv, arch/shared (macOS only)

**`vice/vice-3.9/` — VICE 3.9 source tree:**

- Full VICE 3.9 source as local reference (unmodified, GPLv2)
- Canonical upstream: `vice-emu-code` repo (https://github.com/davidwhittington/vice-emu-code)
- VICE-Team SVN mirror: https://github.com/VICE-Team/svn-mirror

**`docs/MODERNIZATION_BLUEPRINT.md` — full architecture document:**

- Phase-by-phase implementation plan (Phases 1–10)
- cbm-* suite differentiation matrix (cbm-foundation, cbm-swift, cbm-vision, cbm-dynasty)
- net2iec / Meatloaf integration design (Phase 7)
- Physical Commodore drive support via opencbm / XUM1541 / ZoomFloppy (Phase 8)
- VICE threading reference diagram
- Risk assessment table
- fuji-foundation → cbm-foundation mapping table

### Added — net2iec / Meatloaf integration design (Phase 7, planned)

Design documented in `MODERNIZATION_BLUEPRINT.md`. net2iec connects the emulated C64
to Meatloaf network drive servers (https://github.com/idolpx/meatloaf) over TCP,
allowing the emulated machine to browse and load from Meatloaf endpoints. Virtual IEC
devices register for units 9–11 via `serial_device_type_set`. Message protocol mirrors
Meatloaf's TCP IEC bus abstraction. cbm-dynasty includes auto-discovery of Meatloaf
devices on LAN; cbm-foundation scaffolds it as an opt-in Network preference.

### Added — Physical Commodore drive support design (Phase 8, planned)

Design documented in `MODERNIZATION_BLUEPRINT.md`. Physical 1541/1571/1581 drives
connect via USB adapters (ZoomFloppy, XUM1541, 1541 Ultimate II) using the `opencbm`
library. VICE already has partial opencbm support in `src/arch/shared/`; the macOS
arch layer will wire it to the IEC bus for cbm-dynasty. `DriveManagerView` (SwiftUI)
will present per-unit assignment (emulated / virtual / net2iec / physical / netiec)
with live IEC activity indicators. cbm-dynasty ships with opencbm bundled;
cbm-foundation makes it optional at build time (`HAVE_OPENCBM=1` in vice_config.h).
