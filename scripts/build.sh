#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -m)" != "arm64" ]]; then
    echo "This release bundles an Apple Silicon core; build on an arm64 Mac." >&2
    exit 1
fi
swift build -c release
APP="$PWD/dist/Codex Harbor.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/CodexHarbor "$APP/Contents/MacOS/CodexHarbor"
cp Vendor/core/bin/harbor-core "$APP/Contents/Resources/harbor-core"
mkdir -p .build/AppIcon.iconset
swift scripts/make-icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
mkdir -p "$APP/Contents/Resources/en.lproj" "$APP/Contents/Resources/zh-Hans.lproj"
printf '%s\n' '"CFBundleDisplayName" = "Codex Harbor";' > "$APP/Contents/Resources/en.lproj/InfoPlist.strings"
printf '%s\n' '"CFBundleDisplayName" = "Codex Harbor";' > "$APP/Contents/Resources/zh-Hans.lproj/InfoPlist.strings"
cp Vendor/core/LICENSE "$APP/Contents/Resources/THIRD_PARTY_LICENSES.txt"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CodexHarbor</string>
<key>CFBundleIdentifier</key><string>com.gh0stx.codexharbor</string>
<key>CFBundleName</key><string>Codex Harbor</string>
<key>CFBundleDisplayName</key><string>Codex Harbor</string>
<key>CFBundleGetInfoString</key><string>Codex Harbor 1.0.0 · by Gh0stX</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>© 2026 Gh0stX</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP/Contents/Resources/harbor-core"
codesign --force --sign - "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$PWD/dist/CodexHarbor-1.0.0-arm64.zip"
echo "$APP"
