#!/bin/zsh
# Builds dist/Budget Guard.app (universal) and dist/BudgetGuard-<version>.dmg.
# Works without the signing identity (ad hoc signature + warning) and without the Sparkle key (no updates + warning).
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
IDENTITY="Budget Guard Signing"
DIST="$ROOT/dist"
APP="$DIST/Budget Guard.app"
PLIST_SRC="$ROOT/app/Resources/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST_SRC")

echo "Compilation universelle (arm64 + x86_64)…"
(cd app && swift build -c release --arch arm64 --arch x86_64)
BIN_DIR=$(cd app && swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/BudgetGuardApp" "$APP/Contents/MacOS/BudgetGuardApp"
cp "$PLIST_SRC" "$APP/Contents/Info.plist"
cp app/Resources/MenuBarIcon.pdf app/Resources/AppIcon.icns "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Sparkle.framework: SwiftPM binary artifact (universal slice).
SPARKLE=$(find app/.build/artifacts -type d -name Sparkle.framework -path "*macos-arm64_x86_64*" | head -1)
[[ -n "$SPARKLE" ]] || { echo "Sparkle.framework introuvable dans app/.build/artifacts" >&2; exit 1; }
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/BudgetGuardApp"

# Sparkle public key (EdDSA), if the owner has generated one.
KEY_FILE="$ROOT/scripts/sparkle-public-key.txt"
if [[ -s "$KEY_FILE" ]]; then
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $(tr -d '[:space:]' < "$KEY_FILE")" "$APP/Contents/Info.plist"
else
    echo "ATTENTION : scripts/sparkle-public-key.txt absent, build sans mises à jour automatiques (SUPublicEDKey)." >&2
fi

# Signing: inside-out for the nested Sparkle components, then the app.
if security find-identity -p codesigning | grep -q "$IDENTITY"; then
    SIGN="$IDENTITY"
else
    SIGN="-"
    echo "ATTENTION : identité \"$IDENTITY\" absente, signature ad hoc (lancer scripts/setup-signing.sh une fois)." >&2
fi
# No hardened runtime: with an ad hoc or self-signed identity (no Team ID), library validation refuses to load
# Sparkle.framework (verified: dyld "different Team IDs"). Notarization is out of scope, so it is not required.
FLAGS=(--force --sign "$SIGN")
FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for part in "$FW/XPCServices/Installer.xpc" "$FW/XPCServices/Downloader.xpc" "$FW/Autoupdate" "$FW/Updater.app"; do
    [[ -e "$part" ]] && codesign "${FLAGS[@]}" "$part"
done
codesign "${FLAGS[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
codesign "${FLAGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"

# DMG with an /Applications shortcut.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Budget Guard.app"
ln -s /Applications "$STAGE/Applications"
DMG="$DIST/BudgetGuard-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Budget Guard" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "OK : $APP"
echo "OK : $DMG"
