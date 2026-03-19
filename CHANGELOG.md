# Changelog — cbm-foundation / VICE

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Added — Phase 9: dynamic VICE library + in-app download (2026-03-18)

**Goal:** Decouple the VICE emulation core from the app binary. `libvice.dylib` is
built separately, published to GitHub Releases, and downloaded automatically on first
launch. Users and developers can override the source URL for custom builds.

**Architecture:**

- `libvice.dylib` loaded at runtime via `dlopen(RTLD_LAZY | RTLD_GLOBAL)`. The
  `RTLD_GLOBAL` flag makes all VICE symbols available to the arch layer without any
  change to the existing C call sites.

- `VICEEngine.m` — new `+loadVICELibrary:error:` class method. Searches Application
  Support first, then the app bundle. Returns an `NSError` if not found, triggering
  the setup UI.

- `CBMLibraryManager.swift` — `@Observable` download manager. Tracks install state,
  fetches GitHub Releases API for latest tag, downloads via `URLSession` with progress,
  verifies SHA256, installs to `~/Library/Application Support/cbm-foundation/`.
  Supports three URL override mechanisms (env var, file, default GitHub).

- `CBMSetupView.swift` — SwiftUI first-run sheet. States: not installed, update
  available, downloading (progress bar), installed (auto-dismiss), error (retry/quit).
  Shown as a modal window before VICE starts.

- `AppDelegate.m` — `applicationDidFinishLaunching:` now calls `loadVICELibrary:`
  first. On failure, presents setup sheet. On success, proceeds to `startVICEOrQuit`.

**Build system:**

- `project.yml` — removed all VICE source file entries (~350 lines). VICE source tree
  is present as headers-only reference. Added `OTHER_LDFLAGS: -undefined dynamic_lookup`.
  Added preBuildScript warning when `dist/libvice.dylib` is absent.

- `vice/` — converted from local broken symlink to proper git submodule pointing at
  `davidwhittington/vice-emu-code`.

- `scripts/build_vice_dylib.sh` — new script. Compiles VICE from the submodule into a
  universal `dist/libvice.dylib` (arm64 + x86_64). Respects `VICE_SRC` override.
  Outputs checksum and version files alongside the dylib.

- `.github/workflows/build-vice-lib.yml` — CI workflow. Triggers on submodule pointer
  change or build script change. Builds universal dylib, publishes to GitHub Releases
  tagged by VICE commit hash. Idempotent (skips if release exists). Re-tags `latest-vice`.

**Documentation:**

- `docs/DYNAMIC_VICE_DESIGN.md` — full design spec: architecture diagram, component
  descriptions, URL override guide, developer quickstart, trade-offs.

---

### Added — Phase 8: physical drive via opencbm (ZoomFloppy / XUM1541)

**Goal:** Enable real 1541/1571/1581 drives connected via USB adapters (ZoomFloppy,
XUM1541) using VICE's existing opencbm realdevice subsystem.  The dylib loads at
runtime so no install is required at build time; the app degrades gracefully when
`libopencbm.dylib` is absent.

**Implementation:**
- `HAVE_REALDEVICE=1` enabled in `vice_config.h`; uses VICE's bundled
  `src/lib/opencbm.h` for build-time types.
- `dynlib.c` (arch/shared wrapper that `#include`s `dynlib-unix.c`) provides
  `vice_dynlib_open/close/symbol/error` via `dlopen` — already in the build.
- VICE's `realdevice.c` / `opencbmlib.c` / `serial-realdevice.c` compile under
  the flag and do all opencbm driver management.
- `$(SRCROOT)/vice/vice-3.9/src/lib` added to `HEADER_SEARCH_PATHS` so the
  bundled `opencbm.h` resolves without a Homebrew install.

**New files:**
- `PhysDrvManager.h/.m` — ObjC singleton wrapping `realdevice_init()`,
  `serial_realdevice_enable/disable()`, and `serial_device_type_set()`.
  Exposes `setup`, `enableForUnit:error:`, `disableForUnit:`, `available`,
  and `state` (`PhysDrvState`: unavailable / disabled / enabled / error).

**Modified files:**
- `VICEEngine.h/.m` — adds `physicalDriveAvailable`, `enablePhysicalDriveForUnit:error:`,
  `disablePhysicalDriveForUnit:` bridging `PhysDrvManager`.
- `PreferenceModel.swift` — adds `physDriveEnabled` / `physDriveUnit` prefs;
  `applyToVICECore()` enables or disables physical drive based on prefs.
- `PreferencesView.swift` — Drive tab gets a "Physical Drive (ZoomFloppy / XUM1541)"
  section with toggle, unit picker, and live status indicator.
- `CBMFoundationMacOS-Bridging-Header.h` — adds `#import "PhysDrvManager.h"`.
- `project.yml` — adds `src/lib` to header search paths.

### Added — Phase 7: net2iec / Meatloaf TCP bridge

**Goal:** Add a TCP-based network IEC device driver that forwards VICE's IEC bus
operations (units 8–11) to a remote Meatloaf/FujiNet-PC server. C64 programs talk
to units 8–11 as normal disk drives; the I/O travels over TCP using the CBM-NET v1
binary framed protocol.

**Protocol (CBM-NET v1):**
- Request frame: `[OPCODE:1][UNIT:1][SA:1][PAYLOAD_LEN:2LE][PAYLOAD:N]`
- Response frame: `[STATUS:1][PAYLOAD_LEN:2LE][PAYLOAD:N]`
- Opcodes: `OPEN(0x01)`, `CLOSE(0x02)`, `READ(0x03)`, `WRITE(0x04)`, `FLUSH(0x05)`
- Status: `OK(0x00)`, `EOF(0x40)`, `ERROR(0x80)`

**New files:**
- `vice_net2iec.h` — public C API: `vice_net2iec_init/enable/disable/active`
- `vice_net2iec.c` — VICE IEC bus callbacks (`openf/closef/getf/putf/flushf/listenf`)
  registered via `machine_bus_device_attach()` for units 8–11; per-secondary 256-byte
  read buffer issues 64-byte READ requests to amortise TCP round-trips; graceful
  fallback to CBM error 74 when socket is -1.
- `Net2IECManager.h/.m` — ObjC singleton managing the POSIX TCP socket lifecycle:
  non-blocking connect with 5-second timeout, 2-second send/recv timeouts, hands fd
  to `vice_net2iec_enable()` on success.

**Modified files:**
- `vice_mac_sdl.m` — calls `vice_net2iec_init()` in `ui_init_finalize()`.
- `VICEEngine.h/.m` — adds `connectNet2IECToHost:port:completion:`, `disconnectNet2IEC`,
  and `isNet2IECConnected` bridging `Net2IECManager`.
- `PreferenceModel.swift` — `applyToVICECore()` connects or disconnects net2iec based
  on `netIECEnabled` preference.
- `PreferencesView.swift` — Network tab upgraded with host/port fields, live status
  indicator, and "Connect Now" button.
- `CBMFoundationMacOS-Bridging-Header.h` — adds `Net2IECManager.h` import so Swift can
  read connection state.

---

### Added — Phase 6: Multi-machine — C64SC (x64sc) target

**Goal:** Add a second application target for the cycle-exact C64SC emulator (x64sc),
sharing the same Swift UI and ObjC arch layer as the existing C64 (x64) target.
Both targets build from a single `project.yml` with no duplicated configuration.

**Key insight:** In VICE 3.9, `machine_class` was moved out of `c64.c` into the
machine-specific memory files (`c64mem.c` for x64, `c64memsc.c` for x64sc). This
makes `c64.c` truly machine-neutral and allows both targets to share it. The only
conflicting source groups are four `c64/*.c` files and the VIC-II implementation
directory (`vicii/` vs `viciisc/`).

**`project.yml` restructure:**

- Extracted `targetTemplates.VICECoreApp`: ~380 lines of shared VICE source configuration
  (all source groups except vicii/, viciisc/, and the machine-specific c64 files).
- `CBMFoundationMacOS` (x64): template + `vicii/` + `{c64cpu, c64mem, c64model, c64-stubs}.c`
- `CBMFoundationC64SC` (x64sc): template + `viciisc/` + `{c64cpusc, c64memsc, c64scmodel, c64sc-stubs}.c`
- `SWIFT_MODULE_NAME: CBMFoundationMacOS` added to template so both targets generate
  `CBMFoundationMacOS-Swift.h` (avoids AppDelegate.m import mismatch).
- Added `CBMFoundationC64SC` scheme with its own run/archive configuration.

**`app/VICEEngine.h/.m`:**

- `+compiledMachineClass` class method: reads VICE's `machine_class` global at runtime
  (defined in `c64mem.c` as `VICE_MACHINE_C64 = 1` for x64;
  in `c64memsc.c` as `VICE_MACHINE_C64SC = 256` for x64sc). No compile-time defines
  needed — the correct value is determined purely by which source files were linked.

**Result:** `xcodebuild BUILD SUCCEEDED` for both `CBMFoundationMacOS` (x64) and
`CBMFoundationC64SC` (x64sc) on arm64. Each builds to a standalone .app containing
VICE 3.9 C core + full Swift/ObjC UI shell. x64sc uses the cycle-exact VIC-II
implementation (`viciisc/`) which models every clock cycle of the original chip.

---

### Added — Phase 5: SwiftUI panels + pause + NSMenu bar + video settings wiring

**Goal:** Full application shell — pause/resume, application menu bar, Open dialogs,
preferences panel, and Metal video settings wired to UserDefaults at startup and after
each Preferences close.

**Pause (`app/vice_mac_sdl.m`):**

- Replaced stub `ui_pause_active/enable/disable/loop_iteration` with real implementation:
  - `is_paused` volatile flag shared between main thread (toggle) and VICE thread (loop).
  - `pause_loop()`: queued via `vsync_on_vsync_do()`; loops calling
    `mainlock_yield_and_sleep(TICK_PER_SECOND / 60)` while paused, keeping the UI
    responsive at ~60 Hz idle rate.
  - `ui_pause_enable()`: sets `is_paused = 1`, schedules `pause_loop` on next vsync.
  - `ui_pause_disable()`: clears `is_paused`, causing `pause_loop` to exit naturally.
  - Added `#include "vsync.h"` and `#include "archdep_tick.h"` for `vsync_on_vsync_do`,
    `TICK_PER_SECOND`, and `mainlock_yield_and_sleep`.

**VICEEngine.m (`app/VICEEngine.m`):**

- `setPauseEnabled:` wired to `ui_pause_enable()` / `ui_pause_disable()`.

**Metal video settings bridges (`app/VICEMetalView.h/.m`):**

- Added four new C bridge functions (declared in header, implemented in `.m`):
  `Vice_MetalSetBrightness`, `Vice_MetalSetSaturation`, `Vice_MetalSetContrast`,
  `Vice_MetalSetCRTCurvature`. These are callable from Swift via the bridging header.

**Preference wiring (`app/PreferenceModel.swift`):**

- `applyToVICECore()` now calls `applyMetalSettings()` after setting VICE resources.
- `applyMetalSettings()` (new): pushes scanlines, CRT curvature, brightness, saturation,
  contrast, and linear filter to the Metal renderer via the C bridge functions.

**Startup preferences (`app/SwiftUIPanelCoordinator.swift`):**

- `applyStartupPreferences()` (new `@objc` method): calls `prefsModel.load()` then
  `applyToVICECore()`. Called from AppDelegate after the VICE thread is running.

**NSMenu bar + actions (`app/AppDelegate.m`):**

- `buildMenuBar()` constructs the full application menu bar:
  - **c=foundation** menu: About, Preferences…, Services, Hide, Hide Others, Show All, Quit.
  - **File** menu: Open Disk Image…, Open Tape Image…, Open Cartridge…, Media Manager…,
    Save Snapshot…, Load Snapshot….
  - **Machine** menu: Pause/Resume toggle (⌘P), Reset (⌘R), Hard Reset (⌘⇧R),
    Warp Mode toggle (⌘⇧W) with checkmark state.
  - **View** menu: Enter Full Screen (⌃⌘F).
  - **Window** menu: Minimize, Zoom, Bring All to Front; registered with `NSApp.windowsMenu`.
- All Open/Save panels use `NSOpenPanel`/`NSSavePanel` with async completion handlers.
- Pause toggle updates menu item title between "Pause" and "Resume" dynamically.
- Warp toggle updates NSControlStateValue checkmark.
- `applicationDidFinishLaunching:` calls `buildMenuBar` then starts VICE then applies
  startup preferences.

**Result:** Phase 5 complete. NSMenu bar wired; pause/resume functional; video settings
(scanlines, CRT, brightness, saturation, contrast) loaded from UserDefaults and applied
to the Metal renderer at startup and after each Preferences panel close.

---

### Added — Phase 4: Keyboard + joystick input

**Goal:** Physical keyboard and MFi/GameController joystick input reach the VICE
emulation core.

**Keyboard (`app/vice_mac_kbd.c`):**

- Fixed NSEvent modifier flag bit positions: Shift=`1<<17`, Control=`1<<18`,
  Option/Alt=`1<<19`. Previous code had Control at `1<<12` and Alt at `1<<11`
  (both wrong). macOS does not distinguish L/R shift in flags; VICE tracks that
  through the individual Shift key-press events already in the keymap table.
- Fixed cursor key mappings: Right/Up/Down now consistently use their correct
  X11 keysym values (matching VHK_KEY_Right/Up/Down = 0xff53/52/54).

**Joystick (`app/vice_mac_joystick.h/.m`, new):**

- `vice_mac_joystick.m` — GameController framework integration:
  - `vice_mac_joystick_init()`: registers `GCControllerDidConnectNotification` and
    `GCControllerDidDisconnectNotification`; wires `extendedGamepad.valueChangedHandler`
    on each connected controller; controller 0 → VICE port 2 (default for most C64
    games), controller 1 → port 1.
  - `_gamepad_to_vice()`: converts `GCExtendedGamepad` state to VICE joystick bitmask
    (up=1, down=2, left=4, right=8, fire=0x10). Combines D-pad (digital) and left
    thumbstick (25% dead zone). Fire maps to button A, right shoulder, or right trigger.
  - `vice_mac_joystick_poll()`: reads atomic `_joy_state[]` (written by GCController
    callbacks) and calls `joystick_set_value_absolute()` only when state changes.
    Called on the VICE thread from `vsyncarch_presync()` so no extra locking needed.
  - `vice_mac_joystick_shutdown()`: removes observers, zeros state.
  - Thread safety: GCController callbacks write `_Atomic uint16_t _joy_state[2]` with
    `memory_order_relaxed`; VICE thread reads with the same order — safe because the
    worst case is a one-frame stale input, not corruption.

**Wiring (`app/vice_mac_sdl.m`):**

- `ui_init_finalize()`: now calls `vice_mac_kbd_init()` and `vice_mac_joystick_init()`.
- `vsyncarch_presync()`: now calls `vice_mac_joystick_poll()` after event processing.
- `vice_mac_ui_shutdown()`: now calls `vice_mac_joystick_shutdown()` before Metal teardown.

**VICEEngine.m (`app/VICEEngine.m`):**

- `keyDown:modifiers:` / `keyUp:modifiers:` activated; call `vice_mac_key_event()`
  directly (path used by future SwiftUI key injection; NSEvent path in
  `vice_mac_process_pending_events()` is the primary runtime path).

**Result:** `xcodebuild BUILD SUCCEEDED`. Keyboard and GameController joystick input
are fully wired to the VICE emulation core.

---

### Added — Phase 3: Metal renderer — palettized VICE output → ARGB8888 → screen

**Goal:** Each frame rendered by the VICE emulation thread is converted from 8bpp
palettized format to ARGB8888 and displayed via Metal.

**`app/videoarch.h`:**

- Added `argb_buffer` (`uint32_t *`) and `argb_pitch` (`unsigned int`) to
  `video_canvas_s`. These are the ARGB8888 render target that VICE's
  `video_canvas_render()` writes into. `#include <stdint.h>` added for `uint32_t`.

**`app/vice_mac_sdl.m`:**

- Added `#include "palette.h"` and `#include "video.h"` for `palette_t`,
  `video_canvas_render()`, `video_render_setphysicalcolor()`, `video_render_setrawrgb()`,
  `video_render_initraw()`.
- `vice_mac_alloc_argb_buffer()` (new): allocates/reallocates the per-canvas ARGB8888
  render buffer via `lib_malloc`; sets `argb_pitch = width * 4`.
- `video_canvas_create()`: calls `vice_mac_alloc_argb_buffer()` at canvas creation
  time so the render target is ready before the first frame.
- `video_canvas_destroy()`: frees `argb_buffer` via `lib_free`.
- `video_canvas_resize()`: reads `canvas_physical_width/height` from the draw buffer,
  updates `canvas->width/height`, and reallocates the ARGB buffer when dimensions change.
- `video_canvas_set_palette()` (fully implemented): iterates VICE's palette entries,
  packs each as `0xFFRRGGBB`, calls `video_render_setphysicalcolor()` per entry;
  populates the raw RGB channel tables via `video_render_setrawrgb()` (256 entries)
  and calls `video_render_initraw()`. This initialises VICE's render color tables so
  `video_render_main()` can do the inline 8bpp→32bpp conversion.
- `video_canvas_refresh()` (fully implemented): applies `scalex`/`scaley`, clamps to
  canvas bounds, calls `video_canvas_render()` with the ARGB buffer as render target,
  then calls `Vice_DisplayManagerDidReceiveFrame()` to push the frame to the Metal
  display pipeline.

**Result:** `xcodebuild BUILD SUCCEEDED`. Frame path is now complete:
VICE emulation thread renders 8bpp palettized pixels → `video_canvas_refresh()` calls
`video_canvas_render()` (palette lookup → ARGB8888) → `VICEDisplayManager` double-buffers
→ `VICEMetalView.presentFrame:` uploads to `MTLTexture` → Metal fragment shader renders
to screen with optional scanline/CRT effects.

---

### Added — Phase 2: NSWindow + VICEMetalView wired; VICE thread running

**Goal:** Get AppKit running the event loop, NSWindow on screen, Metal view installed,
and the VICE emulation thread alive.

**App lifecycle (`app/`):**

- `main.m` (new): ObjC entry point; creates `NSApplication`, assigns `AppDelegate` as
  delegate, calls `[app run]`. Replaces `main.c` which previously called `main_program()`
  directly (bypassing AppKit). `main.c` excluded from build via `project.yml`.
- `AppDelegate.h/.m` (new): `NSApplicationDelegate` that calls
  `[[VICEEngine sharedEngine] startWithMachine:VICEMachineModelC64 error:nil]` in
  `applicationDidFinishLaunching:`. Shows an `NSAlert` and terminates cleanly on init
  failure. Calls `[[VICEEngine sharedEngine] stop]` on `applicationWillTerminate:`.
  Returns `YES` from `applicationShouldTerminateAfterLastWindowClosed:` so quitting
  the window quits the app.
- `vice_mac_sdl.m` (new): Renamed from `vice_mac_sdl.c` to Objective-C so `NSWindow`,
  `NSApp`, `@autoreleasepool`, and `dispatch_*` are valid. `vice_mac_sdl.c` excluded
  from build. Key additions over Phase 1:
  - `vice_mac_ui_init()`: creates `NSWindow` (768×544, titled, resizable, full-screen
    primary), calls `Vice_MetalViewCreate()` to install VICEMetalView as content view,
    calls `Vice_MetalViewSetDisplayManager()` to wire the frame pipeline, then shows the
    window.
  - `vice_mac_process_pending_events()`: drains `NSEventQueue` on main thread via
    `dispatch_sync`; routes `NSEventTypeKeyDown/Up` to `vice_mac_key_event()`.
  - Added stubs: `main_exit()` (dispatches `[NSApp terminate:nil]`), `ui_init_with_args()`
    (no-op), `video_init()` (returns 0).

**Metal frame pipeline (`app/`):**

- `VICEMetalView.m`: Added `Vice_MetalViewSetDisplayManager()` C bridge; wires
  `[VICEDisplayManager sharedManager].metalView = gMetalView` so that
  `Vice_DisplayManagerDidReceiveFrame()` (called from `video_canvas_refresh()` on the
  VICE thread) forwards ARGB8888 frames into the MTKView for Metal upload and display.
  Added `#import "VICEDisplayManager.h"` import.

**VICE contributor data (`vice/vice-3.9/src/infocontrib.h`):**

- Expanded from minimal stub to define `core_team[]`, `ex_team[]`, `doc_team[]`,
  `trans_team[]` as sentinel-terminated stubs. Required by `vice_banner()` in `main.c`.
  `info_license_text`/`info_warranty_text` remain in `info.c`.

**Result:** `xcodebuild BUILD SUCCEEDED`. Startup flow:
`main()` → AppKit run loop → `applicationDidFinishLaunching:` →
`VICEEngine startWithMachine:C64` → `main_program()` → `ui_init()` →
`vice_mac_ui_init()` (NSWindow + MetalView) → VICE thread spawned → returns →
AppKit run loop drives Metal rendering.

---

### Added — Phase 1: VICE C core compiles and links on arm64 (commit d8627d4)

**Goal:** Full compilation and linking of VICE 3.9 C core with no errors under Xcode/XcodeGen.

**Build system fixes (`project.yml`):**

- Added all required VICE source directories: `drive/iec`, `drive/iec/c64exp`,
  `drive/iec128dcr`, `drive/ieee`, `drive/iecieee`, `drive/tcbm`, `fsdevice`,
  `gfxoutputdrv` (excluding `pngdrv.c`), `samplerdrv`, `diag`, `hvsc`, `lib/md5`,
  `lib/libzmbv`, `sid`, `resid`, `arch/shared` (recursive with `**/*.c`)
- Added `arch/headless` with explicit file list for archdep, machine UI stubs,
  console, kbd, mouse, uimon (replaces SDL arch stubs)
- Excluded non-standalone TUs that must be `#include`d by machine-specific files:
  `*core.c` (6510core, 6510dtvcore, 65816core, 65c02core, aciacore, digimaxcore,
  piacore, z80core), `maincpu.c`, `mainc64cpu.c`, `main65816cpu.c`, `mainviccpu.c`,
  `render-common.c`
- Excluded standalone tools with their own `main()` or linenoise: `c1541.c`,
  `c1541-stubs.c`
- Resolved all duplicate symbol conflicts by selecting x64 over x64sc/VSID/DTV variants:
  - `c64/c64cpusc.c`, `c64/c64memsc.c`, `c64/c64scmodel.c`, `c64/c64sc-stubs.c` (x64sc)
  - `c64/vsid*.c`, `c64/vsid-*.c` (VSID standalone player — 14 files)
  - `vicii/viciidtv-*.c` (C64DTV-specific vicii variants)
  - `viciisc/` entire directory (conflicts with `vicii/`)
  - `sid/resid-dtv.cc` + `resid-dtv/` C++ engine (DTV SID — not needed for x64)
  - `resid/filter.cc` excluded in favour of `resid/filter8580new.cc`
    (`NEW_8580_FILTER=1` hardcoded in `siddefs.h`)
  - `arch/shared/dynlib-unix.c` (included by `dynlib.c`),
    `arch/shared/rs232-unix-dev.c` (included by `rs232dev.c`)
  - `arch/shared/archdep_get_vice_datadir.c` (provided in `vice_mac_sdl.c`)
  - `arch/headless/uistatusbar.c` (provided as stubs in `vice_mac_sdl.c`)
  - `gfxoutputdrv/pngdrv.c` (requires libpng — Phase 5)
  - Non-macOS audio drivers, Windows-only arch/shared files

**macOS arch layer (`app/`):**

- `videoarch.h` (new): macOS arch `video_canvas_s` struct definition with all fields
  required by VICE core — `initialized`, `created`, `index`, `depth`, `width/height`,
  `real_width/height`, `actual_width/height`, `videoconfig`, `crt_type`, `draw_buffer`,
  `draw_buffer_vsid`, `viewport`, `geometry`, `palette`, `parent_raster`,
  `warp_next_render_tick`. Defines `MAX_CANVAS_NUM 2`, `VIDEO_CANVAS_IDX_VDC/VICII`.
- `vice_config.h`: added `VICE_DATADIR` and `VICE_DOCDIR` defines
- `vice_mac_sdl.c`: full implementation of `uiapi.h`, `vsyncapi.h`, `videoarch.h`
  contracts; global variables from excluded `main.c` (`console_mode`,
  `help_requested`, `default_settings_requested`, `video_disabled_mode`,
  `maincpu_stretch`, `c128cpu_memory_refresh_clk`); hotkey arch pass-through stubs;
  stubs for `main_exit`, `vice_thread_shutdown`, `archdep_thread_init/shutdown`,
  `gfxoutput_init_png`, `output_graphics_*`, `soundmovie_*`, `userport_wic64_*`
- `vice_mac_kbd.c`: keyboard matrix translation using `VHK_KEY_*` constants from
  `vhkkeysyms.h`; macOS hardware key codes to VICE key symbols via 256-entry table

**Result:** `xcodebuild` reports `BUILD SUCCEEDED`. arm64 binary: `CBMFoundationMacOS`
(55K launcher) + `CBMFoundationMacOS.debug.dylib` (5.7M VICE core).

---

### Added — Initial scaffold: cbm-foundation macOS emulator app

**Project scope defined:** cbm-foundation is the 1:1 macOS port of VICE 3.9 for Commodore
hardware, modeled on the fuji-foundation / Atari800MacX pattern. It is the foundation app in
the cbm-* suite (cbm-foundation, cbm-swift, cbm-vision, cbm-dynasty).

**`app/` — macOS app layer (Phase 1–5 scaffold):**

- `CBMFoundationApp.swift` — minimal Swift entry point, AppKit app lifecycle
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
- `CBMFoundationMacOS-Bridging-Header.h` — Swift/ObjC bridging header
- `CBMFoundationMacOS.entitlements` — app sandbox entitlements

**`CBMFoundationMacOS.xcodeproj` / `project.yml` (XcodeGen):**

- Single app target `CBMFoundationMacOS`, macOS 14.0, Swift 5.9
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
