#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v node >/dev/null 2>&1; then
    echo "Node.js is required to build the Windows app." >&2
    exit 1
fi
if ! command -v npm >/dev/null 2>&1; then
    echo "npm is required to build the Windows app." >&2
    exit 1
fi
export ELECTRON_MIRROR="${ELECTRON_MIRROR:-https://npmmirror.com/mirrors/electron/}"
npm install
DIST="$PWD/../dist/windows"
mkdir -p "$DIST"
for arch in x64 arm64; do
    npx electron-packager . "Codex Harbor" \
        --platform=win32 \
        --arch="$arch" \
        --out="$DIST" \
        --overwrite \
        --no-asar \
        --icon=assets/icon.ico \
        --app-version=1.0.0 \
        --app-copyright="© 2026 Gh0stX" \
        --win32metadata.CompanyName=Gh0stX \
        --win32metadata.ProductName="Codex Harbor" \
        --ignore="^/node_modules($|/)" \
        --ignore="^/dist($|/)" \
        --prune=true
    ZIP="$PWD/../dist/CodexHarbor-1.0.0-win32-$arch.zip"
    rm -f "$ZIP"
    if command -v zip >/dev/null 2>&1; then
        (cd "$DIST" && zip -q -r -X "$ZIP" "Codex Harbor-win32-$arch")
    elif command -v ditto >/dev/null 2>&1; then
        ditto -c -k --norsrc --keepParent "$DIST/Codex Harbor-win32-$arch" "$ZIP"
    else
        echo "Install zip (or use macOS ditto) to create the portable archive." >&2
        exit 1
    fi
    echo "$ZIP"
done
if command -v makensis >/dev/null 2>&1; then
    "$PWD/installer/build-installers.sh"
else
    echo "makensis not found; portable builds are ready, installers were skipped." >&2
    echo "Install it with: brew install makensis" >&2
fi
