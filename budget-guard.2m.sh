#!/bin/bash
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideSwiftBar>false</swiftbar.hideSwiftBar>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
#
# Budget Guard — SwiftBar plugin (refreshes every 2 min)
# Shows Claude Max usage in macOS menu bar.
# Version: 1.2.0

set -u

# --- Ensure Homebrew and system binaries are in PATH (SwiftBar has a minimal PATH) ---
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# --- Configuration ---
API_MODEL="claude-haiku-4-5-20251001"
API_URL="https://api.anthropic.com/v1/messages"
API_TIMEOUT=8
API_CONNECT_TIMEOUT=3
KEYCHAIN_SERVICE="Claude Code-credentials"
CACHE_FILE="$HOME/.claude/budget-cache.json"
LOG_FILE="$HOME/.claude/budget-guard.log"
DEBUG=${BUDGET_GUARD_DEBUG:-0}

# Notification thresholds (percentage)
NOTIFY_WARN=80
NOTIFY_CRIT=95

# --- Logging ---
log() {
    [[ "$DEBUG" == "1" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# --- Check dependencies ---
if ! command -v python3 &>/dev/null; then
    echo "CC: ERR | size=13 color=red"
    echo "---"
    echo "python3 not found | size=12"
    echo "Install with: brew install python3 | size=11 color=gray"
    exit 0
fi

# --- Format percentage (pure awk, no python) ---
fmt_pct() {
    local val="$1"
    if [[ "$val" == "?" ]]; then echo "?"; return; fi
    awk "BEGIN { v=$val; if(v<=1) printf \"%.0f\", v*100; else printf \"%.0f\", v }"
}

# --- Color based on usage level ---
get_color() {
    local pct="$1"
    if [[ "$pct" == "?" ]]; then echo "gray"; return; fi
    # Tones: <70% light green, 70-89% light orange, >=90% light red
    if (( pct >= 90 )); then echo "#FF8080"
    elif (( pct >= 70 )); then echo "#FFB866"
    else echo "#9EF59E"
    fi
}

# --- macOS notification (once per threshold) ---
notify_threshold() {
    local pct="$1" threshold="$2" label="$3"
    local flag_file="$HOME/.claude/.budget-notified-${threshold}"
    if (( pct >= threshold )) && [[ ! -f "$flag_file" ]]; then
        osascript -e "display notification \"Claude usage at ${pct}%\" with title \"Budget Guard\" subtitle \"${label} threshold reached\"" 2>/dev/null
        touch "$flag_file"
        log "Notification sent: ${pct}% >= ${threshold}%"
    elif (( pct < threshold )) && [[ -f "$flag_file" ]]; then
        rm -f "$flag_file"
    fi
}

# --- Validate that a string is a number ---
is_number() {
    [[ "$1" =~ ^[0-9]*\.?[0-9]+$ ]]
}

# --- Get fresh usage from rate-limit headers ---
get_usage_from_headers() {
    local token
    token=$(security find-generic-password -s "$KEYCHAIN_SERVICE" -w 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])" 2>/dev/null)

    if [[ -z "${token:-}" ]]; then
        log "Failed to retrieve token from Keychain"
        return 1
    fi

    # Pass token securely via temp file (not visible in ps output)
    local header_file
    header_file=$(mktemp)
    chmod 600 "$header_file"
    printf 'Authorization: Bearer %s' "$token" > "$header_file"
    unset token

    local headers
    headers=$(curl -s -D - -o /dev/null \
        --max-time "$API_TIMEOUT" \
        --connect-timeout "$API_CONNECT_TIMEOUT" \
        -H @"$header_file" \
        -H "Content-Type: application/json" \
        -H "anthropic-version: 2023-06-01" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -X POST "$API_URL" \
        -d "{\"model\":\"$API_MODEL\",\"max_tokens\":1,\"messages\":[{\"role\":\"user\",\"content\":\"h\"}]}" 2>/dev/null)

    rm -f "$header_file"

    if [[ -z "${headers:-}" ]]; then
        log "curl returned empty response"
        return 1
    fi

    # Check HTTP status code
    local http_code
    http_code=$(echo "$headers" | head -1 | awk '{print $2}')
    log "HTTP status: ${http_code:-unknown}"

    if [[ "${http_code:-}" == "429" ]]; then
        log "Rate limited (429) — budget likely exhausted"
        echo "1.0|now|?"
        return 0
    fi

    if [[ "${http_code:-}" != "200" ]]; then
        log "Unexpected HTTP status: ${http_code:-unknown}"
        return 1
    fi

    # Since late 2026 the 5-hour window is gone: only the 7-day window (and overage) remain.
    local u7 reset7 uo ostatus oreason
    u7=$(echo "$headers" | grep -i "anthropic-ratelimit-unified-7d-utilization" | tr -d '\r' | awk '{print $2}')
    reset7=$(echo "$headers" | grep -i "anthropic-ratelimit-unified-7d-reset" | tr -d '\r' | awk '{print $2}')
    uo=$(echo "$headers" | grep -i "anthropic-ratelimit-unified-overage-utilization" | tr -d '\r' | awk '{print $2}')
    ostatus=$(echo "$headers" | grep -i "anthropic-ratelimit-unified-overage-status" | tr -d '\r' | awk '{print $2}')
    oreason=$(echo "$headers" | grep -i "anthropic-ratelimit-unified-overage-disabled-reason" | tr -d '\r' | awk '{print $2}')

    if ! is_number "${u7:-}"; then
        log "No valid 7d utilization header found (u7='${u7:-}')"
        return 1
    fi
    is_number "${uo:-}" || uo="?"

    python3 - "$u7" "${reset7:-0}" "$uo" "${ostatus:-?}" "${oreason:-}" <<'PYEOF'
import sys
from datetime import datetime, timezone

u7, reset7_raw, uo, ostatus, oreason = sys.argv[1:6]

def fmt_reset(ts):
    if not ts or ts == '0':
        return '?'
    try:
        delta = int(ts) - datetime.now(timezone.utc).timestamp()
        if delta <= 0:
            return 'now'
        d = int(delta) // 86400
        h = (int(delta) % 86400) // 3600
        m = (int(delta) % 3600) // 60
        if d > 0:
            return f'{d}d {h}h'
        return f'{h}h {m}m' if h > 0 else f'{m}m'
    except (ValueError, TypeError):
        return '?'

# Overage: utilization if reported, otherwise its status ("off: out_of_credits")
if uo != '?':
    overage = f'{round(float(uo) * 100)}%'
elif ostatus == 'rejected':
    overage = f'off ({oreason})' if oreason else 'off'
else:
    overage = ostatus
print(f'{u7}|{fmt_reset(reset7_raw)}|{overage}')
PYEOF
}

# --- Fetch data ---
PARSED=$(get_usage_from_headers)
if [[ $? -eq 0 && -n "${PARSED:-}" ]]; then
    U7=$(echo "$PARSED" | cut -d'|' -f1)
    R7=$(echo "$PARSED" | cut -d'|' -f2)
    OV=$(echo "$PARSED" | cut -d'|' -f3)

    # Update cache with timestamp and secure permissions
    python3 - "$U7" "$R7" "$OV" "$CACHE_FILE" <<'PYEOF'
import json, sys, os
from datetime import datetime, timezone
u7, r7, ov, cache_path = float(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
fd = os.open(cache_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, 'w') as f:
    json.dump({
        'seven_day': u7,
        'reset_7d': r7,
        'overage': ov,
        'updated_at': datetime.now(timezone.utc).isoformat(),
    }, f)
PYEOF
    log "Cache updated: u7=$U7 overage=$OV"
else
    # API failed — try reading existing cache (tolerates the pre-1.1 cache format)
    if [[ -f "$CACHE_FILE" ]]; then
        CACHED=$(python3 - "$CACHE_FILE" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
ov = d.get('overage', '?')
if isinstance(ov, (int, float)):
    ov = f'{round(ov * 100)}%'
print(f"{d.get('seven_day', '?')}|{d.get('reset_7d', '?')}|{ov}|{d.get('updated_at', '?')}")
PYEOF
        )
        U7=$(echo "$CACHED" | cut -d'|' -f1)
        R7=$(echo "$CACHED" | cut -d'|' -f2)
        OV=$(echo "$CACHED" | cut -d'|' -f3)
        log "Using cached data from $(echo "$CACHED" | cut -d'|' -f4)"
    else
        U7="?"; R7="?"; OV="?"
        log "No cache available, showing '?'"
    fi
fi

# --- Format percentage, color, notifications ---
U7_PCT=$(fmt_pct "${U7:-?}")
COLOR=$(get_color "$U7_PCT")

if [[ "$U7_PCT" != "?" ]]; then
    notify_threshold "$U7_PCT" "$NOTIFY_WARN" "Warning (${NOTIFY_WARN}%)"
    notify_threshold "$U7_PCT" "$NOTIFY_CRIT" "Critical (${NOTIFY_CRIT}%)"
fi

# --- Menu bar title ---
echo "CC: ${U7_PCT}$([[ "$U7_PCT" != "?" ]] && echo %) | size=13 color=${COLOR}"

echo "---"

# --- Usage details ---
echo "Weekly usage: ${U7_PCT}$([[ "$U7_PCT" != "?" ]] && echo %) | size=12"
echo "Resets in: ${R7} | size=12"
echo "Overage: ${OV} | size=12"

echo "---"

# --- Actions ---
echo "Open Anthropic Console | href=https://console.anthropic.com/settings/usage"
echo "Refresh | refresh=true"

if [[ "$DEBUG" == "1" ]]; then
    echo "---"
    echo "Debug mode ON | size=10 color=gray"
    echo "Log: $LOG_FILE | size=10 color=gray"
fi
