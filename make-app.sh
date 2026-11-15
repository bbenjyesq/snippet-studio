#!/bin/bash
# Builds Snippet Studio and installs it as a normal Mac app in ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="$HOME/Applications/Snippet Studio.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/SnippetStudio "$APP/Contents/MacOS/SnippetStudio"

# App icon: Resources/AppIcon.png (1024 px) made into the .icns file macOS wants, with Apple's built-in tools.
mkdir -p "$APP/Contents/Resources"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>SnippetStudio</string>
    <key>CFBundleIdentifier</key><string>io.github.bbenjyesq.snippetstudio</string>
    <key>CFBundleName</key><string>Snippet Studio</string>
    <key>CFBundleDisplayName</key><string>Snippet Studio</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
# shortcut: ad-hoc signature runs on this Mac only; other Macs need a Developer ID signature.
codesign --force --sign - "$APP"
touch "$APP" # nudges Finder and the Dock to pick up the new icon

echo ""
echo "Installed: $APP"
echo "Open it from Spotlight (Command-Space, type Snippet Studio) or Launchpad."
