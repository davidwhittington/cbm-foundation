#!/usr/bin/env bash
# build_vice_dylib.sh — compile VICE 3.9 into a universal libvice.dylib
#
# Usage:
#   scripts/build_vice_dylib.sh                   # default: build from submodule
#   VICE_SRC=/path/to/vice scripts/build_vice_dylib.sh  # override source location
#
# Output: dist/libvice.dylib (universal arm64 + x86_64)
#         dist/libvice.dylib.sha256
#         dist/libvice-version.txt (VICE commit hash)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VICE_SRC="${VICE_SRC:-$REPO_ROOT/vice}"
DIST_DIR="$REPO_ROOT/dist"
BUILD_DIR="$REPO_ROOT/build/vice"
OUTPUT="$DIST_DIR/libvice.dylib"

# Minimum macOS target
MACOS_MIN="14.0"

echo "==> cbm-foundation: building libvice.dylib"
echo "    source: $VICE_SRC"
echo "    output: $OUTPUT"
echo

if [ ! -d "$VICE_SRC/src" ]; then
    echo "ERROR: VICE source not found at $VICE_SRC/src"
    echo "  Run: git submodule update --init vice"
    echo "  Or set VICE_SRC=/path/to/your/vice"
    exit 1
fi

mkdir -p "$BUILD_DIR/arm64" "$BUILD_DIR/x86_64" "$DIST_DIR"

# Source file list — mirrors project.yml exactly
VICE_SRCS=$(cd "$VICE_SRC/src" && find \
    . \
    c64 c64/cart \
    video vicii viciisc raster \
    sid resid \
    drive drive/iec drive/iec/c64exp drive/iec128dcr drive/ieee drive/iecieee drive/tcbm \
    iecbus serial tape tapeport joyport \
    core core/rtc diskimage vdrive datasette imagecontents fileio \
    parallel userport rs232drv monitor vdc printerdrv \
    fsdevice gfxoutputdrv samplerdrv diag hvsc lib/md5 lib/libzmbv \
    arch/shared \
    -maxdepth 1 -name "*.c" -o -name "*.cc" -o -name "*.m" 2>/dev/null | \
    grep -v \
        -e "main\.c$" \
        -e "c64cpusc\.c" -e "c64memsc\.c" -e "c64scmodel\.c" -e "c64sc-stubs\.c" \
        -e "vsid" \
        -e "c64dtv" \
        -e "resid-dtv" \
        -e "dynlib-unix\.c" -e "rs232-unix-dev\.c" \
        -e "archdep_get_vice_datadir\.c" \
        -e "uistatusbar\.c" \
        -e "pngdrv\.c" \
        -e "soundalsa\|soundbeos\|soundbsp\|sounddx\|soundpulse\|soundsdl\|soundsun\|soundwmm\|soundflac\|soundvorbis\|soundmp3\|soundmovie\|lamelib" \
        -e "arch/sdl\|arch/gtk3" \
    | sort)

COMMON_FLAGS="\
    -DMACOSX=1 \
    -DUNIX_COMPILE=1 \
    -DUSE_VICE_THREAD=1 \
    -DVICE_ARCHTYPE_NATIVE_MACOS=1 \
    -DHAVE_AUDIO_UNIT=1 \
    -DHAVE_CONFIG_H=1 \
    -DHAVE_REALDEVICE=1 \
    -I$VICE_SRC/src \
    -I$VICE_SRC/src/c64 \
    -I$VICE_SRC/src/vicii \
    -I$VICE_SRC/src/sid \
    -I$VICE_SRC/src/drive \
    -I$VICE_SRC/src/iecbus \
    -I$VICE_SRC/src/video \
    -I$VICE_SRC/src/core \
    -I$VICE_SRC/src/raster \
    -I$VICE_SRC/src/arch/shared \
    -I$VICE_SRC/src/arch/headless \
    -I$VICE_SRC/src/lib \
    -I$REPO_ROOT/apps/cbm-foundation-app \
    -Wno-unused-parameter \
    -Wno-sign-compare \
    -Wno-missing-field-initializers \
    -Wno-deprecated-declarations \
    -Wno-implicit-function-declaration \
    -fPIC"

compile_arch() {
    local ARCH="$1"
    local OUT_DIR="$BUILD_DIR/$ARCH"
    mkdir -p "$OUT_DIR"
    echo "  Compiling for $ARCH..."

    (cd "$VICE_SRC/src" && \
     echo "$VICE_SRCS" | tr '\n' '\0' | xargs -0 \
        clang -arch "$ARCH" \
            -mmacosx-version-min="$MACOS_MIN" \
            $COMMON_FLAGS \
            -c -o /dev/null 2>/dev/null || true)

    # Compile each file to object in parallel
    local OBJECTS=()
    while IFS= read -r src; do
        [ -z "$src" ] && continue
        local obj="$OUT_DIR/$(echo "$src" | tr '/' '_').o"
        local ext="${src##*.}"
        if [ "$ext" = "cc" ]; then
            clang++ -arch "$ARCH" -mmacosx-version-min="$MACOS_MIN" \
                $COMMON_FLAGS \
                -include "$VICE_SRC/src/config.h" \
                -x c++ -std=gnu++17 \
                -c "$VICE_SRC/src/$src" -o "$obj" 2>/dev/null &
        else
            clang -arch "$ARCH" -mmacosx-version-min="$MACOS_MIN" \
                $COMMON_FLAGS \
                -c "$VICE_SRC/src/$src" -o "$obj" 2>/dev/null &
        fi
        OBJECTS+=("$obj")
    done <<< "$VICE_SRCS"
    wait

    echo "  Linking $ARCH dylib..."
    clang -arch "$ARCH" \
        -mmacosx-version-min="$MACOS_MIN" \
        -dynamiclib \
        -install_name "@rpath/libvice.dylib" \
        -framework CoreAudio -framework AudioUnit -framework AudioToolbox \
        -framework CoreFoundation \
        -o "$BUILD_DIR/libvice.$ARCH.dylib" \
        "${OBJECTS[@]}" 2>/dev/null
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

# Record VICE version
VICE_COMMIT=$(cd "$VICE_SRC" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
echo "$VICE_COMMIT" > "$DIST_DIR/libvice-version.txt"

# Checksum
shasum -a 256 "$OUTPUT" | awk '{print $1}' > "$OUTPUT.sha256"

echo
echo "==> Done"
echo "    $OUTPUT"
echo "    SHA256: $(cat "$OUTPUT.sha256")"
echo "    VICE commit: $VICE_COMMIT"
