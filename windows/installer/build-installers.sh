#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$PWD"
DIST="$ROOT/dist"
if ! command -v makensis >/dev/null 2>&1; then
    echo "makensis is required. Install it with: brew install makensis" >&2
    exit 1
fi
for arch in x64 arm64; do
    APPDIR="$DIST/windows/Codex Harbor-win32-$arch"
    if [[ ! -d "$APPDIR" ]]; then
        echo "Portable app not found: $APPDIR" >&2
        echo "Run windows/scripts/build-windows.sh first." >&2
        exit 1
    fi
    OUTFILE="$DIST/CodexHarbor-1.0.0-win32-$arch-setup.exe"
    rm -f "$OUTFILE"
    makensis \
        -DARCH="$arch" \
        -DAPPDIR="$APPDIR" \
        -DOUTFILE="$OUTFILE" \
        -DICONFILE="$ROOT/windows/assets/icon.ico" \
        -DLICENSEFILE="$ROOT/windows/installer/LICENSE.txt" \
        "$ROOT/windows/installer/installer.nsi"
    echo "$OUTFILE"
done
