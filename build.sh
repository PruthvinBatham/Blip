#!/bin/bash
# Builds Blip.app. Needs only the Command Line Tools — no Xcode, no SPM deps.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Blip.app"
BIN="$APP/Contents/MacOS/Blip"
RES="$APP/Contents/Resources"

rm -rf build
mkdir -p "$(dirname "$BIN")" "$RES"

echo "› compiling"
swiftc -swift-version 5 -O \
  -target arm64-apple-macos14.0 \
  Sources/*.swift \
  -o "$BIN"

echo "› Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Blip</string>
  <key>CFBundleDisplayName</key><string>Blip</string>
  <key>CFBundleExecutable</key><string>Blip</string>
  <key>CFBundleIdentifier</key><string>com.pruthvin.blip</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <!-- Agent app: lives in the menu bar, never in the Dock or app switcher. -->
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Pruthvin Batham</string>
</dict>
</plist>
PLIST

echo "› icon"
"$BIN" --iconset build/AppIcon.iconset >/dev/null
if command -v iconutil >/dev/null 2>&1; then
  iconutil -c icns build/AppIcon.iconset -o "$RES/AppIcon.icns"
else
  echo "  (iconutil missing — shipping without an icon)"
fi

echo "› signing (ad-hoc)"
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "  (unsigned — fine for local use)"

echo "✓ built $APP"
