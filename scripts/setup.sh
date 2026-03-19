#!/usr/bin/env bash
# setup.sh — one-time developer setup for cbm-foundation
#
# Run this after cloning:
#   git clone ... cbm-foundation
#   cd cbm-foundation
#   scripts/setup.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> cbm-foundation setup"

# 1. Submodule
echo "  Initializing submodules..."
git submodule update --init --recursive

# 2. vice-3.9 compatibility symlink
# vice-emu-code repo layout: vice/src/  (no version subdirectory)
# project.yml and HEADER_SEARCH_PATHS reference vice/vice-3.9/src/
# A symlink bridges the two without changing any paths.
VICE_LINK="$REPO_ROOT/vice/vice-3.9"
if [ ! -e "$VICE_LINK" ]; then
    echo "  Creating vice/vice-3.9 → vice compatibility symlink..."
    ln -s . "$VICE_LINK"
fi

# 3. XcodeGen
if ! command -v xcodegen &>/dev/null; then
    echo "  Installing xcodegen..."
    brew install xcodegen
fi
echo "  Generating Xcode project..."
xcodegen generate

# 4. libvice.dylib
APP_SUPPORT="$HOME/Library/Application Support/cbm-foundation"
DIST_LIB="$REPO_ROOT/dist/libvice.dylib"
INSTALLED_LIB="$APP_SUPPORT/libvice.dylib"

mkdir -p "$APP_SUPPORT"

if [ -f "$INSTALLED_LIB" ]; then
    echo "  libvice.dylib already installed ($(cat "$APP_SUPPORT/libvice-version.txt" 2>/dev/null || echo 'version unknown'))"
elif [ -f "$DIST_LIB" ]; then
    echo "  Copying dist/libvice.dylib to Application Support..."
    cp "$DIST_LIB" "$INSTALLED_LIB"
    [ -f "$REPO_ROOT/dist/libvice-version.txt" ] && cp "$REPO_ROOT/dist/libvice-version.txt" "$APP_SUPPORT/"
else
    echo
    echo "  libvice.dylib not found. Options:"
    echo "    A) Download pre-built (fastest):"
    echo "       gh release download --repo davidwhittington/cbm-foundation \\"
    echo "         --pattern 'libvice.dylib' --dir '$APP_SUPPORT'"
    echo
    echo "    B) Build from source (~5 min):"
    echo "       scripts/build_vice_dylib.sh"
    echo "       cp dist/libvice.dylib '$INSTALLED_LIB'"
    echo
    echo "    C) Skip — the app will prompt to download on first launch."
    echo
fi

echo
echo "==> Setup complete."
echo "    Open CBMFoundationMacOS.xcodeproj in Xcode and build the CBMFoundationMacOS scheme."
