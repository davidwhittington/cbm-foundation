#!/usr/bin/env bash
# build_vice_dylib.sh — compile VICE into a universal libvice.dylib
#
# Usage:
#   scripts/build_vice_dylib.sh
#   VICE_SRC=/path/to/vice scripts/build_vice_dylib.sh
#
# Output:
#   dist/libvice.dylib       — universal arm64 + x86_64
#   dist/libvice.dylib.sha256
#   dist/libvice-version.txt

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VICE_SRC="${VICE_SRC:-$REPO_ROOT/vice}"
DIST_DIR="$REPO_ROOT/dist"
BUILD_DIR="$REPO_ROOT/build/vice"
OUTPUT="$DIST_DIR/libvice.dylib"
MACOS_MIN="14.0"
JOBS=$(sysctl -n hw.logicalcpu)

echo "==> cbm-foundation: building libvice.dylib"
echo "    source: $VICE_SRC"
echo "    output: $OUTPUT"
echo "    jobs:   $JOBS"
echo

if [ ! -d "$VICE_SRC/src" ]; then
    echo "ERROR: VICE source not found at $VICE_SRC/src"
    echo "  Run: git submodule update --init vice"
    exit 1
fi

mkdir -p "$BUILD_DIR/arm64" "$BUILD_DIR/x86_64" "$DIST_DIR"

S="$VICE_SRC/src"

# Write a clang response file — one flag per line, no quoting/expansion issues
write_flags() {
    local ARCH="$1"
    local RSPFILE="$2"
    cat > "$RSPFILE" << EOF
-arch $ARCH
-mmacosx-version-min=$MACOS_MIN
-DMACOSX=1
-DUNIX_COMPILE=1
-DUSE_VICE_THREAD=1
-DVICE_ARCHTYPE_NATIVE_MACOS=1
-DHAVE_AUDIO_UNIT=1
-DHAVE_CONFIG_H=1
-DHAVE_REALDEVICE=1
-Wno-unused-parameter
-Wno-sign-compare
-Wno-missing-field-initializers
-Wno-deprecated-declarations
-Wno-implicit-function-declaration
-Wno-macro-redefined
-Wno-int-conversion
-Wno-incompatible-pointer-types
-fPIC
-I$REPO_ROOT/app
-I$S
-I$S/c64
-I$S/c64/cart
-I$S/c64dtv
-I$S/c128
-I$S/c128/cart
-I$S/cbm2
-I$S/cbm2/cart
-I$S/pet
-I$S/pet/cart
-I$S/plus4
-I$S/plus4/cart
-I$S/vic20
-I$S/vic20/cart
-I$S/scpu64
-I$S/video
-I$S/vicii
-I$S/viciisc
-I$S/vdc
-I$S/raster
-I$S/sid
-I$S/resid
-I$S/drive
-I$S/drive/iec
-I$S/drive/iec/c64exp
-I$S/drive/iec128dcr
-I$S/drive/ieee
-I$S/drive/iecieee
-I$S/drive/tcbm
-I$S/iecbus
-I$S/serial
-I$S/tape
-I$S/tapeport
-I$S/datasette
-I$S/joyport
-I$S/userport
-I$S/parallel
-I$S/rs232drv
-I$S/core
-I$S/core/rtc
-I$S/diskimage
-I$S/vdrive
-I$S/imagecontents
-I$S/fileio
-I$S/monitor
-I$S/printerdrv
-I$S/fsdevice
-I$S/cartridge
-I$S/gfxoutputdrv
-I$S/samplerdrv
-I$S/diag
-I$S/hvsc
-I$S/lib
-I$S/lib/p64
-I$S/lib/md5
-I$S/lib/libzmbv
-I$S/arch/shared
-I$S/arch/shared/sounddrv
-I$S/arch/shared/hwsiddrv
-I$S/arch/shared/hotkeys
-I$S/arch/shared/socketdrv
-I$S/arch/headless
EOF
}

# Source files — C64 (x64) machine only, matching the CFoundationMacX Xcode target.
# Excludes all other machine variants to prevent duplicate symbol errors.
VICE_SRCS=$(cd "$S" && find . \( -name "*.c" -o -name "*.cc" -o -name "*.m" \) | \
    grep -v \
        -e "arch/sdl/" -e "arch/gtk3/" \
        -e "THIS_PLACEHOLDER_NEVER_MATCHES" \
        -e "c64dtv/" -e "resid-dtv" -e "vsid" \
        -e "viciidtv" \
        -e "^./tools/" \
        -e "c64cpusc\.c" -e "c64memsc\.c" -e "c64scmodel\.c" -e "c64sc-stubs\.c" \
        -e "viciisc/" \
        -e "^./c128/" -e "^./cbm2/" -e "^./pet/" -e "^./plus4/" \
        -e "^./vic20/" -e "^./scpu64/" \
        -e "arch/headless/vsyncarch\.c" \
        -e "arch/headless/video\.c" \
        -e "arch/headless/ui\.c" \
        -e "arch/headless/kbd\.c" \
        -e "arch/headless/c128ui\|arch/headless/cbm2ui\|arch/headless/cbm5x0ui" \
        -e "arch/headless/petui\|arch/headless/plus4ui\|arch/headless/vic20ui" \
        -e "arch/headless/scpu64ui\|arch/headless/vsidui\|arch/headless/c64dtvui" \
        -e "vdc/" \
        -e "dynlib-unix\.c" -e "rs232-unix-dev\.c" \
        -e "archdep_get_vice_datadir\.c" \
        -e "uistatusbar\.c" -e "pngdrv\.c" \
        -e "6510core\.c" -e "6510dtvcore" -e "65816core" -e "65c02core" \
        -e "aciacore" -e "digimaxcore" -e "piacore" -e "z80core" \
        -e "maincpu\.c" -e "mainc64cpu" -e "main65816cpu" -e "mainviccpu" \
        -e "render-common\.c" \
        -e "c1541\.c" -e "c1541-stubs" -e "linenoise" \
        -e "soundalsa" -e "soundbeos" -e "soundbsp" -e "sounddx" \
        -e "soundpulse" -e "soundsdl" -e "soundsun" -e "soundwmm" \
        -e "soundflac" -e "soundvorbis" -e "soundmp3" -e "soundmovie" -e "lamelib" \
        -e "rs232-win32" -e "dynlib-win32" -e "rawnetarch_win32" \
        -e "archdep_is_windows" -e "socket-win32" -e "hardsid-win32" \
        -e "catweasel.*win32" -e "parsid-win32" \
        -e "console_unix" -e "console_none" -e "^./console\.c" \
        -e "filter\.cc$" \
    | sort)

SOURCE_COUNT=$(echo "$VICE_SRCS" | grep -c "." || true)
echo "  Source files: $SOURCE_COUNT"

compile_arch() {
    local ARCH="$1"
    local OUT_DIR="$BUILD_DIR/$ARCH"
    mkdir -p "$OUT_DIR"

    # Write response file for this arch
    local RSPFILE="$BUILD_DIR/flags.$ARCH.rsp"
    write_flags "$ARCH" "$RSPFILE"

    echo "  Compiling $ARCH ($JOBS parallel jobs)..."

    # Write a compile script that uses the response file
    local COMPILE_SCRIPT="$BUILD_DIR/compile.$ARCH.sh"
    > "$COMPILE_SCRIPT"

    local OBJECTS=()
    while IFS= read -r src; do
        [ -z "$src" ] && continue
        local obj="$OUT_DIR/$(echo "$src" | tr '/' '_' | sed 's/^\.//' ).o"
        OBJECTS+=("$obj")
        local ext="${src##*.}"
        local srcpath="$S/$src"
        if [ "$ext" = "cc" ]; then
            echo "clang++ @$RSPFILE -include $REPO_ROOT/app/config.h -x c++ -std=gnu++17 -c \"$srcpath\" -o \"$obj\" 2>/dev/null || true" >> "$COMPILE_SCRIPT"
        else
            echo "clang @$RSPFILE -c \"$srcpath\" -o \"$obj\" 2>/dev/null || true" >> "$COMPILE_SCRIPT"
        fi
    done <<< "$VICE_SRCS"

    # Run compile commands in parallel using background jobs + semaphore
    local RUNNING=0
    while IFS= read -r cmd; do
        [ -z "$cmd" ] && continue
        eval "$cmd" &
        RUNNING=$((RUNNING + 1))
        if [ $RUNNING -ge $JOBS ]; then
            wait
            RUNNING=0
        fi
    done < "$COMPILE_SCRIPT"
    wait

    # Count successes
    local BUILT=0
    local FINAL_OBJECTS=()
    for obj in "${OBJECTS[@]}"; do
        if [ -f "$obj" ] && [ -s "$obj" ]; then
            FINAL_OBJECTS+=("$obj")
            BUILT=$((BUILT + 1))
        fi
    done

    echo "  $BUILT / ${#OBJECTS[@]} objects compiled"

    if [ ${#FINAL_OBJECTS[@]} -eq 0 ]; then
        echo "ERROR: no objects to link" >&2; return 1
    fi

    echo "  Linking $ARCH dylib..."
    clang -arch "$ARCH" \
        -mmacosx-version-min="$MACOS_MIN" \
        -dynamiclib \
        -undefined dynamic_lookup \
        -install_name "@rpath/libvice.dylib" \
        -framework CoreAudio -framework AudioUnit -framework AudioToolbox \
        -framework CoreFoundation -framework Foundation \
        -o "$BUILD_DIR/libvice.$ARCH.dylib" \
        "${FINAL_OBJECTS[@]}"
}

echo "  Building arm64..."
compile_arch arm64

echo "  Building x86_64..."
compile_arch x86_64

echo "  Creating universal binary..."
lipo -create \
    "$BUILD_DIR/libvice.arm64.dylib" \
    "$BUILD_DIR/libvice.x86_64.dylib" \
    -output "$OUTPUT"

VICE_COMMIT=$(cd "$VICE_SRC" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
echo "$VICE_COMMIT" > "$DIST_DIR/libvice-version.txt"
shasum -a 256 "$OUTPUT" | awk '{print $1}' > "$OUTPUT.sha256"

echo
echo "==> Done"
echo "    $OUTPUT  ($(du -sh "$OUTPUT" | awk '{print $1}'))"
echo "    SHA256: $(cat "$OUTPUT.sha256")"
echo "    VICE commit: $VICE_COMMIT"
