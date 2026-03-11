#!/usr/bin/env bash
# sync_vice_data.sh
# Copies VICE ROM/keymap data from vice/src/data/ into the app bundle Resources.
# Run this whenever VICE source is updated.
#
# Usage: ./scripts/sync_vice_data.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."
VICE_DATA="$ROOT/vice/src/data"
DEST="$ROOT/apps/cfoundation-app/Resources/vice-data"

if [ ! -d "$VICE_DATA" ]; then
    echo "Error: vice/src/data not found. Run 'git submodule update' or copy VICE source to vice/."
    exit 1
fi

mkdir -p "$DEST"

# C64 ROMs and keymaps
rsync -a --delete "$VICE_DATA/C64/"   "$DEST/C64/"
rsync -a --delete "$VICE_DATA/DRIVES/" "$DEST/DRIVES/" 2>/dev/null || true

echo "Synced VICE data to $DEST"
echo "C64 files: $(ls "$DEST/C64" | wc -l | tr -d ' ')"
