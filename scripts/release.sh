#!/bin/zsh
# Publie une version : build, appcast Sparkle (local), GitHub Release, commit et push de l'appcast.
# À lancer par le propriétaire uniquement, depuis master, une fois le feu vert donné.
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
REPO="dalex160/claude-budget-watch"
die() { echo "REFUS : $*" >&2; exit 1; }

# --- Prérequis (tout est vérifié avant de construire ou de publier quoi que ce soit) ---
[[ -z "$(git status --porcelain)" ]] || die "des modifications ne sont pas commitées."
[[ "$(git branch --show-current)" == "master" ]] || die "il faut être sur la branche master."
command -v gh >/dev/null || die "gh (GitHub CLI) est absent."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/app/Resources/Info.plist")
TAG="v$VERSION"
[[ -s "$ROOT/scripts/sparkle-public-key.txt" ]] || die "scripts/sparkle-public-key.txt manque (étape propriétaire : générer la clé Sparkle avec generate_keys puis y coller la clé publique)."
IDENTITIES=$(security find-identity -p codesigning 2>/dev/null || true)
[[ "$IDENTITIES" == *"Budget Guard Signing"* ]] || die "identité \"Budget Guard Signing\" absente (étape propriétaire : lancer scripts/setup-signing.sh)."
security find-generic-password -s "https://sparkle-project.org" -a ed25519 >/dev/null 2>&1 || die "clé privée Sparkle absente du trousseau (étape propriétaire : lancer generate_keys sur ce Mac)."

RELEASE_EXISTS=0
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    RELEASE_EXISTS=1
    if grep -q "<sparkle:shortVersionString>$VERSION<" "$ROOT/site/appcast.xml" 2>/dev/null; then
        die "la release $TAG existe déjà et l'appcast la contient : version déjà publiée (augmenter la version dans Info.plist). Pour repartir de zéro : gh release delete $TAG --cleanup-tag"
    fi
    echo "La release $TAG existe mais l'appcast ne la contient pas : reprise sans la recréer."
fi

# --- Build ---
"$ROOT/scripts/build-app.sh"

APP="$ROOT/dist/Budget Guard.app"
DMG="$ROOT/dist/BudgetGuard-$VERSION.dmg"
[[ -f "$DMG" ]] || die "$DMG introuvable."
SIGINFO=$(codesign -dv "$APP" 2>&1 || true)
[[ "$SIGINFO" != *"Signature=adhoc"* ]] || die "l'app est signée ad hoc."
/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$APP/Contents/Info.plist" >/dev/null 2>&1 || die "SUPublicEDKey absente de l'app."

# --- Appcast local (avant toute publication) ---
GEN=$(find "$ROOT/app/.build/artifacts" -type f -name generate_appcast -path "*sparkle*" | head -1)
[[ -x "$GEN" ]] || die "generate_appcast introuvable (compiler l'app une fois)."
STABLE_DIR=$(mktemp -d)
FEED_DIR=$(mktemp -d)
trap 'rm -rf "$STABLE_DIR" "$FEED_DIR"' EXIT
[[ -f "$ROOT/site/appcast.xml" ]] && cp "$ROOT/site/appcast.xml" "$FEED_DIR/appcast.xml"
cp "$DMG" "$FEED_DIR/"
"$GEN" "$FEED_DIR" --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" -o "$FEED_DIR/appcast.xml"
grep -q "<sparkle:shortVersionString>$VERSION<" "$FEED_DIR/appcast.xml" || die "l'appcast généré ne contient pas la version $VERSION."
mkdir -p "$ROOT/site"
cp "$FEED_DIR/appcast.xml" "$ROOT/site/appcast.xml"

# --- Publication ---
if (( RELEASE_EXISTS == 0 )); then
    # Nom stable pour le bouton « Télécharger » (releases/latest/download/BudgetGuard.dmg), en plus du nom versionné.
    cp "$DMG" "$STABLE_DIR/BudgetGuard.dmg"
    gh release create "$TAG" "$DMG" "$STABLE_DIR/BudgetGuard.dmg" --repo "$REPO" --title "Budget Guard $VERSION" --generate-notes
fi

git add site/appcast.xml
git commit -m "release: Budget Guard $VERSION" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin master
echo "OK : $TAG publiée, appcast mis à jour."
