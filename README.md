# cbm-foundation

A native macOS Commodore emulator — modernized GUI, Metal rendering, and network hardware integration.

Built on [VICE 3.9](https://vice-emu.sourceforge.io/) (GPLv2). Modeled on the fuji-foundation / Atari800MacX pattern.

## Current Status

Early scaffold. Phase 1 (Xcode project + VICE core compilation) in progress.

## What This Is

cbm-foundation is the 1:1 macOS port of the VICE Commodore emulator. It wraps the VICE C emulation core in a modern native macOS app:

- **Metal rendering** — replaces VICE's SDL/OpenGL display output
- **SwiftUI panels** — Preferences, Machine Selector, Media Manager
- **Native macOS input** — NSEvent keyboard + GameController.framework joysticks
- **net2iec protocol** — connects to [Meatloaf](https://github.com/idolpx/meatloaf) network drive servers
- **Physical drive support** — real 1541/1571/1581 drives via USB adapters (opencbm)
- **NetIEC protocol** — scaffolded UDP bridge for FujiNet-PC integration

## The CBM Suite

cbm-foundation is the base app in a four-app suite:

| App | Platform | Scope |
|-----|----------|-------|
| **cbm-foundation** | macOS 14+ | 1:1 VICE port — full feature set, all machines |
| **cbm-swift** | macOS 14+ | Stripped down — C64 only, minimal UI, fast |
| **cbm-vision** | visionOS 2+ | Spatial — 3D bezel, mixed reality retro computing |
| **cbm-dynasty** | macOS 14+ | Everything — all add-ons, net2iec, Meatloaf, physical drives |

## Supported Machines

| Machine | Phase |
|---------|-------|
| Commodore 64 | Phase 1 |
| Commodore 64 (cycle-exact) | Phase 1 |
| Commodore 128 | Phase 3+ |
| VIC-20 | Phase 4+ |
| PET | Phase 5+ |
| Plus/4 | Phase 5+ |

## Repo Layout

```
apps/cfoundation-app/   macOS app layer (Swift + ObjC + C arch layer)
vice/                   VICE 3.9 source tree (unmodified, GPLv2)
scripts/                Build and release scripts
docs/                   MODERNIZATION_BLUEPRINT.md and architecture notes
CHANGELOG.md            All notable changes
```

## Architecture

The VICE C core is compiled unchanged from `vice/src/`. The macOS arch layer (`vice_mac_sdl.c`) replaces `vice/src/arch/sdl/` entirely. An ObjC bridge (`VICEEngine`) is the only interface between Swift/GUI code and the C core.

See [`docs/MODERNIZATION_BLUEPRINT.md`](docs/MODERNIZATION_BLUEPRINT.md) for the full phase-by-phase plan.

## Related Repos

- [vice-emu-code](https://github.com/davidwhittington/vice-emu-code) — VICE C core upstream tracking
- [meatloaf](https://github.com/idolpx/meatloaf) — Meatloaf IEC network device (net2iec target)

## VICE Upstream

VICE source: tracked in [vice-emu-code](https://github.com/davidwhittington/vice-emu-code)
SVN upstream: https://svn.code.sf.net/p/vice-emu/code/trunk
VICE-Team GitHub mirror: https://github.com/VICE-Team/svn-mirror

## Naming

Brand name: **c=foundation** (the `=` is the Commodore logo glyph)
Filesystem/repo: `cbm-foundation`

## License

VICE is licensed under the GNU General Public License v2.
The cbm-foundation app layer (new code in `apps/`) is copyright David Whittington.
The combined work, when distributed, is subject to GPL v2.
See `apps/cfoundation-app/Resources/COPYING` for the GPL v2 text.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).
