# Budget Guard

**Keep your Claude Max usage visible in the macOS menu bar.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Budget Guard is a [SwiftBar](https://github.com/swiftbar/SwiftBar) plugin that displays your Claude Max rate-limit consumption (5-hour and 7-day windows) directly in the macOS menu bar. No more surprise throttles.

---

## What it does

- Shows **5h** and **7d** usage percentages at a glance: `CC: 42% / 18%`
- Displays time until each rate-limit window resets in the dropdown
- Caches the last known values so the menu bar stays populated even if an API call fails
- Refreshes automatically every 2 minutes

## Prerequisites

| Requirement | Notes |
|---|---|
| **macOS** | Uses Keychain for credential storage |
| **SwiftBar** | Install from [swiftbar.app](https://swiftbar.app) or `brew install --cask swiftbar` |
| **Claude Max subscription** | The plugin reads rate-limit headers from the Anthropic API |
| **python3** | Ships with macOS (used for JSON parsing and percentage formatting) |
| **Claude Code** | Must have been authenticated at least once so the OAuth token is in Keychain |

## Installation

### Option A -- Symlink (recommended)

This way you can `git pull` updates without re-copying.

```bash
git clone https://github.com/alexmusic/budget-guard.git ~/budget-guard

# Create a symlink in SwiftBar's plugin directory
ln -s ~/budget-guard/budget-guard.2m.sh "$HOME/Library/Application Support/SwiftBar/Plugins/budget-guard.2m.sh"
```

### Option B -- Direct copy

```bash
git clone https://github.com/alexmusic/budget-guard.git ~/budget-guard

cp ~/budget-guard/budget-guard.2m.sh "$HOME/Library/Application Support/SwiftBar/Plugins/"
```

After either method, make sure the script is executable:

```bash
chmod +x "$HOME/Library/Application Support/SwiftBar/Plugins/budget-guard.2m.sh"
```

SwiftBar will pick it up automatically on the next refresh cycle.

## How it works

1. **Reads the OAuth token** from the macOS Keychain (`Claude Code-credentials`).
2. **Sends a minimal API request** to `api.anthropic.com` (a single-token Haiku call) just to receive rate-limit response headers.
3. **Parses the headers** for `anthropic-ratelimit-unified-5h-utilization`, `anthropic-ratelimit-unified-7d-utilization`, and their corresponding reset timestamps.
4. **Caches the result** to `~/.claude/budget-cache.json` so the display survives transient API failures.
5. **Outputs SwiftBar-formatted text** for the menu bar title and dropdown.

The API call costs virtually nothing -- it is a single-token Haiku request whose only purpose is to retrieve rate-limit headers.

## Configuration

### Refresh interval

The refresh interval is encoded in the filename, following the SwiftBar convention. The default `budget-guard.2m.sh` refreshes every **2 minutes**. Rename the file (or symlink) to change it:

| Filename | Interval |
|---|---|
| `budget-guard.30s.sh` | 30 seconds |
| `budget-guard.2m.sh` | 2 minutes (default) |
| `budget-guard.5m.sh` | 5 minutes |

### Cache file

The cache is stored at `~/.claude/budget-cache.json`. You can delete it safely -- it will be recreated on the next successful API call.

## License

MIT -- see [LICENSE](LICENSE).
