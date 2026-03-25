#!/bin/bash
#
# Budget Guard Installer
# Installs the SwiftBar plugin and optionally installs SwiftBar itself.

set -euo pipefail

PLUGIN_NAME="budget-guard.2m.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SWIFTBAR_PLUGINS_DIR="$HOME/Library/Application Support/SwiftBar/Plugins"

echo ""
echo "==================================="
echo "  Budget Guard Installer"
echo "==================================="
echo ""

# --- Check for SwiftBar ---
if ! ls /Applications/SwiftBar.app &>/dev/null && ! ls "$HOME/Applications/SwiftBar.app" &>/dev/null; then
    echo "[!] SwiftBar is not installed."
    echo ""
    read -rp "    Install SwiftBar via Homebrew? (y/n) " answer
    if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
        if ! command -v brew &>/dev/null; then
            echo "[ERROR] Homebrew is not installed. Please install SwiftBar manually:"
            echo "        https://swiftbar.app"
            exit 1
        fi
        echo "[*] Installing SwiftBar..."
        brew install --cask swiftbar
        echo "[OK] SwiftBar installed."
    else
        echo ""
        echo "    Please install SwiftBar first: https://swiftbar.app"
        echo "    Then re-run this installer."
        exit 1
    fi
fi

# --- Check for python3 ---
if ! command -v python3 &>/dev/null; then
    echo "[!] python3 is not found in PATH."
    echo "    Budget Guard requires python3. Install it with:"
    echo "      brew install python3"
    exit 1
fi

# --- Check for Claude Code credentials ---
if ! security find-generic-password -s "Claude Code-credentials" &>/dev/null 2>&1; then
    echo "[!] Claude Code credentials not found in Keychain."
    echo "    Make sure you have authenticated Claude Code at least once."
    echo "    Run: claude"
    echo ""
    echo "    The plugin will still be installed but won't work until you authenticate."
    echo ""
fi

# --- Create plugins directory ---
mkdir -p "$SWIFTBAR_PLUGINS_DIR"

# --- Copy plugin ---
SOURCE="$SCRIPT_DIR/$PLUGIN_NAME"
DEST="$SWIFTBAR_PLUGINS_DIR/$PLUGIN_NAME"

if [[ ! -f "$SOURCE" ]]; then
    echo "[ERROR] Cannot find $PLUGIN_NAME in $SCRIPT_DIR"
    exit 1
fi

cp "$SOURCE" "$DEST"
chmod +x "$DEST"

echo "[OK] Plugin installed to:"
echo "     $DEST"
echo ""

# --- Create cache directory ---
mkdir -p "$HOME/.claude"

# --- Launch SwiftBar if not running ---
if ! pgrep -x "SwiftBar" &>/dev/null; then
    echo "[*] Starting SwiftBar..."
    open -a SwiftBar
    echo "[OK] SwiftBar launched."
else
    echo "[*] SwiftBar is already running. The plugin will appear on next refresh."
fi

echo ""
echo "==================================="
echo "  Installation complete!"
echo "==================================="
echo ""
echo "  You should see 'CC: xx% / xx%' in your menu bar shortly."
echo ""
echo "  Troubleshooting:"
echo "    - Enable debug: export BUDGET_GUARD_DEBUG=1"
echo "    - Logs: ~/.claude/budget-guard.log"
echo ""
