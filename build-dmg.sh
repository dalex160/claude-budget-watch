#!/bin/bash
#
# Builds a distributable DMG for Budget Guard.
#
# Usage: ./build-dmg.sh
# Output: Budget-Guard-Installer.dmg

set -euo pipefail

APP_NAME="Budget Guard"
DMG_NAME="Budget-Guard-Installer"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build-dmg"
DMG_CONTENTS="$BUILD_DIR/dmg-contents"
DMG_OUTPUT="$SCRIPT_DIR/$DMG_NAME.dmg"

echo "[*] Building $DMG_NAME.dmg..."

# --- Clean previous build ---
rm -rf "$BUILD_DIR"
rm -f "$DMG_OUTPUT"
mkdir -p "$DMG_CONTENTS"

# --- Copy files into DMG staging area ---
cp "$SCRIPT_DIR/budget-guard.2m.sh" "$DMG_CONTENTS/"
cp "$SCRIPT_DIR/install.sh" "$DMG_CONTENTS/"
cp "$SCRIPT_DIR/LICENSE" "$DMG_CONTENTS/"
cp "$SCRIPT_DIR/README.md" "$DMG_CONTENTS/"
chmod +x "$DMG_CONTENTS/install.sh"
chmod +x "$DMG_CONTENTS/budget-guard.2m.sh"

# --- Create a clickable installer app bundle ---
# This wraps install.sh in a minimal .app so users can double-click it.
INSTALLER_APP="$DMG_CONTENTS/Install Budget Guard.app"
MACOS_DIR="$INSTALLER_APP/Contents/MacOS"
RESOURCES_DIR="$INSTALLER_APP/Contents/Resources"

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Launcher script that opens Terminal and runs the installer
cat > "$MACOS_DIR/launcher" <<'LAUNCHER'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")/../../../" && pwd)"
INSTALL_SCRIPT="$SCRIPT_DIR/install.sh"
open -a Terminal "$INSTALL_SCRIPT"
LAUNCHER
chmod +x "$MACOS_DIR/launcher"

# Info.plist
cat > "$INSTALLER_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>launcher</string>
    <key>CFBundleIdentifier</key>
    <string>com.alexisdahan.budget-guard-installer</string>
    <key>CFBundleName</key>
    <string>Install Budget Guard</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
PLIST

# --- Create the DMG ---
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_CONTENTS" \
    -ov \
    -format UDZO \
    "$DMG_OUTPUT" \
    2>/dev/null

# --- Clean up ---
rm -rf "$BUILD_DIR"

echo "[OK] DMG created: $DMG_OUTPUT"
echo "     Size: $(du -h "$DMG_OUTPUT" | awk '{print $1}')"
