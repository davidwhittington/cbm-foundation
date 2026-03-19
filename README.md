# cbm-foundation

A native macOS Commodore emulator — Metal rendering, SwiftUI panels, and network hardware integration built on [VICE 3.9](https://vice-emu.sourceforge.io/) (GPLv2).

## Current Status

**Phase 8 complete.** Core emulation, Metal rendering, audio, keyboard/joystick input, multi-machine builds, net2iec network drives, and physical drive access via opencbm are all implemented and building. The app runs the VICE C64 emulation core natively on macOS 14+ (Apple Silicon and Intel).

See [CHANGELOG.md](CHANGELOG.md) for the full history.

## What This Is

c=foundation wraps the VICE C emulation core in a modern native macOS app:

- **Metal rendering** — replaces VICE's SDL/OpenGL display with a Metal shader pipeline (scanlines, CRT curvature, brightness/saturation/contrast)
- **SwiftUI panels** — Preferences, Machine Selector, Media Manager
- **Native macOS input** — NSEvent keyboard mapping, GameController.framework joysticks
- **net2iec** — IEC bus forwarded over TCP to a [Meatloaf](https://github.com/idolpx/meatloaf) or FujiNet-PC server
- **Physical drive support** — real 1541/1571/1581 drives via ZoomFloppy/XUM1541 adapters (opencbm, runtime dylib)
- **Multi-machine targets** — separate Xcode targets for C64 (x64) and C64SC (x64sc); architecture ready for C128, VIC-20, PET, Plus/4

## How to Build

**Requirements:**

- macOS 14+, Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

**Steps:**

```bash
git clone https://github.com/davidwhittington/cbm-foundation
cd cbm-foundation
xcodegen generate
open CFoundationMacX.xcodeproj
```

Build the `CFoundationMacX` scheme in Xcode, or from the command line:

```bash
xcodebuild -scheme CFoundationMacX -configuration Debug build
```

**Optional runtime dependencies** (not required to build):

- `brew install opencbm` — physical drive access via ZoomFloppy/XUM1541
- A Meatloaf or FujiNet-PC server for net2iec network drives

## Supported Machines

| Machine | Target | Status |
|---------|--------|--------|
| Commodore 64 | `CFoundationMacX` | Running |
| Commodore 64 (cycle-exact) | `CFoundationC64SC` | Running |
| Commodore 128 | — | Planned |
| VIC-20 | — | Planned |
| PET | — | Planned |
| Plus/4 | — | Planned |

## Repo Layout

```
apps/cfoundation-app/   macOS app layer (Swift + ObjC + C arch layer)
vice/vice-3.9/          VICE 3.9 source tree (unmodified, GPLv2)
scripts/                Build and release scripts
docs/                   Architecture notes and modernization blueprint
project.yml             XcodeGen project definition
CHANGELOG.md            All notable changes
```

## Architecture

The VICE C core compiles unchanged from `vice/vice-3.9/src/`. The macOS arch layer (`vice_mac_sdl.m`) replaces `arch/sdl/` entirely. An ObjC bridge (`VICEEngine`) is the sole interface between Swift/GUI code and the C core — no Swift touches VICE directly.

```
Swift (SwiftUI + @Observable)
    ↓  bridging header
ObjC (VICEEngine, VICEMetalView, Net2IECManager, PhysDrvManager)
    ↓  C headers (mainlock, resources, serial, ...)
C   (VICE 3.9 core — unmodified)
```

See [`docs/MODERNIZATION_BLUEPRINT.md`](docs/MODERNIZATION_BLUEPRINT.md) for the full phase-by-phase plan.

## Related Repos

- [vice-emu-code](https://github.com/davidwhittington/vice-emu-code) — VICE upstream tracking (SVN trunk)
- [meatloaf](https://github.com/idolpx/meatloaf) — Meatloaf IEC network device (net2iec target)

## Naming

Brand name: **c=foundation** (the `=` is the Commodore logo glyph)
Filesystem/repo: `cbm-foundation`

## License

VICE is licensed under the GNU General Public License v2.
The cbm-foundation app layer (new code in `apps/`) is copyright David Whittington.
The combined work, when distributed, is subject to GPL v2.
See `apps/cfoundation-app/Resources/COPYING` for the GPL v2 text.
