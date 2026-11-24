#!/bin/zsh
# Publie une version : build, GitHub Release, appcast Sparkle, commit et push.
# À lancer par le propriétaire uniquement, depuis master, une fois le feu vert donné.
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
REPO="dalex160/claude-budget-watch"
die() { echo "REFUS : $*" >&2; exit 1; }

[[ -z "$(git status --porcelain)" ]] || die "des modifications ne sont pas commitées."
[[ "$(git branch --show-current)" == "master" ]] || die "il faut être sur la branche master."
command -v gh >/dev/null || die "gh (GitHub CLI) est absent."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/app/Resources/Info.plist")
TAG="v$VERSION"
[[ -s "$ROOT/scripts/sparkle-public-key.txt" ]] || die "scripts/sparkle-public-key.txt manque (étape propriétaire : générer la clé Sparkle avec generate_keys)."
security find-identity -p codesigning | grep -q "Budget Guard Signing" || die "identité \"Budget Guard Signing\" absente (étape propriétaire : lancer scripts/setup-signing.sh)."
! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 || die "la release $TAG existe déjà (augmenter la version dans Info.plist)."

"$ROOT/scripts/build-app.sh"

APP="$ROOT/dist/Budget Guard.app"
DMG="$ROOT/dist/BudgetGuard-$VERSION.dmg"
[[ -f "$DMG" ]] || die "$DMG introuvable."
codesign -dv "$APP" 2>&1 | grep -q "Signature=adhoc" && die "l'app est signée ad hoc."
/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$APP/Contents/Info.plist" >/dev/null 2>&1 || die "SUPublicEDKey absente de l'app."

# Nom stable pour le bouton « Télécharger » (releases/latest/download/BudgetGuard.dmg), en plus du nom versionné.
STABLE_DIR=$(mktemp -d)
FEED_DIR=$(mktemp -d)
trap 'rm -rf "$STABLE_DIR" "$FEED_DIR"' EXIT
cp "$DMG" "$STABLE_DIR/BudgetGuard.dmg"
gh release create "$TAG" "$DMG" "$STABLE_DIR/BudgetGuard.dmg" --repo "$REPO" --title "Budget Guard $VERSION" --generate-notes

# L'appcast ne référence que le DMG versionné (URL figée par version).
GEN=$(find "$ROOT/app/.build/artifacts" -type f -name generate_appcast -path "*sparkle*" | head -1)
[[ -x "$GEN" ]] || die "generate_appcast introuvable (compiler l'app une fois)."
mkdir -p "$ROOT/site"
[[ -f "$ROOT/site/appcast.xml" ]] && cp "$ROOT/site/appcast.xml" "$FEED_DIR/appcast.xml"
cp "$DMG" "$FEED_DIR/"
"$GEN" "$FEED_DIR" --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" -o "$FEED_DIR/appcast.xml"
cp "$FEED_DIR/appcast.xml" "$ROOT/site/appcast.xml"

git add site/appcast.xml
git commit -m "release: Budget Guard $VERSION" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin master
echo "OK : $TAG publiée, appcast mis à jour."
