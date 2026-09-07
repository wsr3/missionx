#!/bin/bash
# Builds a SwiftPM executable and wraps it in a signed .app bundle. Does the job
# Xcode would normally do, so only the Command Line Tools are required.
#
#   ./build.sh                                    # the app
#   ./build.sh AXProbe com.missionx.axprobe       # a diagnostic tool
set -euo pipefail

PRODUCT="${1:-MissionX}"
BUNDLE_ID="${2:-com.missionx.app}"
DISPLAY_NAME="${3:-$PRODUCT}"

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/$DISPLAY_NAME.app"

echo "==> Compiling $PRODUCT"
swift build -c release --product "$PRODUCT"
BINARY="$(swift build -c release --product "$PRODUCT" --show-bin-path)/$PRODUCT"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$DISPLAY_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>$DISPLAY_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>$DISPLAY_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# A stable identity keeps the accessibility permission across rebuilds; run
# ./dev-cert.sh to create it. Ad-hoc signing works but is revoked every rebuild.
IDENTITY="MissionX Dev"
if ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "==> WARNING: '$IDENTITY' not found, falling back to ad-hoc signing."
    echo "    Accessibility permission will reset on every rebuild. Run ./dev-cert.sh."
    IDENTITY="-"
fi

echo "==> Signing with: $IDENTITY"
codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
codesign -dv "$APP" 2>&1 | grep -E "^Identifier|^Authority" || true

echo "==> Done: $APP"
