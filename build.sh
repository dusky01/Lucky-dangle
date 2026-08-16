#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="LuckyDangle.app"
CONTENTS="$APP/Contents"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Lucky Dangle</string>
    <key>CFBundleDisplayName</key><string>Lucky Dangle</string>
    <key>CFBundleIdentifier</key><string>app.luckydangle.clone</string>
    <key>CFBundleExecutable</key><string>LuckyDangle</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
PLIST

# bundle the charm artwork
if [ -d charms ]; then
    mkdir -p "$CONTENTS/Resources/charms"
    cp charms/*.png "$CONTENTS/Resources/charms/"
fi

echo "Compiling…"
swiftc -O \
    -o "$CONTENTS/MacOS/LuckyDangle" \
    src/main.swift \
    -framework Cocoa -framework Carbon

# Ad-hoc sign so macOS lets it run locally
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "Built $APP"
