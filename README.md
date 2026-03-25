# Budget Guard

**Keep your Claude Max usage visible in the macOS menu bar.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Budget Guard is a [SwiftBar](https://github.com/swiftbar/SwiftBar) plugin that displays your Claude Max rate-limit consumption (5-hour and 7-day windows) directly in the macOS menu bar. No more surprise throttles.

---

## What it does

- Shows **5h** and **7d** usage percentages at a glance: `CC: 42% / 18%`
- **Color-coded** display: green, yellow, orange, red depending on usage level
- **macOS notifications** when usage crosses 80% and 95% thresholds
- Displays time until each rate-limit window resets in the dropdown
- Detects **429 rate-limit** responses and shows 100% immediately
- Caches the last known values so the menu bar stays populated even if an API call fails
- Quick link to **Anthropic Console** usage dashboard in dropdown
- Refreshes automatically every 2 minutes

## Prerequisites

| Requirement | Notes |
|---|---|
| **macOS** | Uses Keychain for credential storage |
| **SwiftBar** | Install from [swiftbar.app](https://swiftbar.app) or `brew install --cask swiftbar` |
| **Claude Max subscription** | The plugin reads rate-limit headers from the Anthropic API |
| **python3** | Ships with macOS (used for JSON parsing and time formatting) |
| **Claude Code** | Must have been authenticated at least once so the OAuth token is in Keychain |

## Installation

### Option A -- Homebrew (recommended)

```bash
brew install --cask swiftbar        # if not already installed
brew tap dalex160/budget-guard
brew install budget-guard
budget-guard-link                    # links the plugin into SwiftBar
```

### Option B -- DMG installer

1. Download the latest `.dmg` from the [Releases](https://github.com/dalex160/claude-budget-guard/releases) page
2. Open the DMG and run **Install Budget Guard**
3. The installer will set up SwiftBar (if needed) and install the plugin

### Option C -- Symlink (recommended for developers)

This way you can `git pull` updates without re-copying.

```bash
git clone https://github.com/dalex160/claude-budget-guard.git ~/budget-guard

# Create a symlink in SwiftBar's plugin directory
mkdir -p "$HOME/Library/Application Support/SwiftBar/Plugins"
ln -sf ~/budget-guard/budget-guard.2m.sh "$HOME/Library/Application Support/SwiftBar/Plugins/budget-guard.2m.sh"
```

### Option D -- Direct copy

```bash
git clone https://github.com/dalex160/claude-budget-guard.git ~/budget-guard

mkdir -p "$HOME/Library/Application Support/SwiftBar/Plugins"
cp ~/budget-guard/budget-guard.2m.sh "$HOME/Library/Application Support/SwiftBar/Plugins/"
chmod +x "$HOME/Library/Application Support/SwiftBar/Plugins/budget-guard.2m.sh"
```

SwiftBar will pick it up automatically on the next refresh cycle.

## How it works

1. **Reads the OAuth token** from the macOS Keychain (`Claude Code-credentials`).
2. **Sends a minimal API request** to `api.anthropic.com` (a single-token Haiku call) just to receive rate-limit response headers. The token is passed securely via a temporary file, not exposed in process arguments.
3. **Parses the headers** for `anthropic-ratelimit-unified-5h-utilization`, `anthropic-ratelimit-unified-7d-utilization`, and their corresponding reset timestamps.
4. **Detects HTTP 429** responses and immediately shows 100% usage.
5. **Caches the result** to `~/.claude/budget-cache.json` (with timestamp) so the display survives transient API failures.
6. **Outputs SwiftBar-formatted text** with color coding for the menu bar title and dropdown.

## Configuration

All configuration constants are at the top of the script for easy editing:

| Variable | Default | Description |
|---|---|---|
| `API_MODEL` | `claude-haiku-4-5-20251001` | Model used for the probe request |
| `API_TIMEOUT` | `8` | Max time for API call (seconds) |
| `API_CONNECT_TIMEOUT` | `3` | Connection timeout (seconds) |
| `NOTIFY_WARN` | `80` | Warning notification threshold (%) |
| `NOTIFY_CRIT` | `95` | Critical notification threshold (%) |

### Refresh interval

The refresh interval is encoded in the filename, following the SwiftBar convention. The default `budget-guard.2m.sh` refreshes every **2 minutes**. Rename the file (or symlink) to change it:

| Filename | Interval |
|---|---|
| `budget-guard.30s.sh` | 30 seconds |
| `budget-guard.2m.sh` | 2 minutes (default) |
| `budget-guard.5m.sh` | 5 minutes |

### Debug mode

Enable detailed logging to troubleshoot issues:

```bash
export BUDGET_GUARD_DEBUG=1
```

Logs are written to `~/.claude/budget-guard.log`.

### Cache file

The cache is stored at `~/.claude/budget-cache.json` with `600` permissions. You can delete it safely -- it will be recreated on the next successful API call.

## Color coding

The menu bar text changes color based on the highest usage percentage:

| Usage | Color |
|---|---|
| < 50% | Green |
| 50-69% | Yellow |
| 70-89% | Orange |
| >= 90% | Red |

## Notifications

Budget Guard sends macOS notifications when usage crosses configured thresholds:

- **80%** -- Warning: time to slow down
- **95%** -- Critical: approaching hard limit

Notifications are sent once per threshold crossing and reset automatically when usage drops below the threshold.

## Building the DMG

To build a distributable DMG:

```bash
./build-dmg.sh
```

This creates `Budget-Guard-Installer.dmg` in the project root.

## License

MIT -- see [LICENSE](LICENSE).
