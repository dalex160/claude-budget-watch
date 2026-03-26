#!/bin/bash
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideSwiftBar>false</swiftbar.hideSwiftBar>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
#
# Budget Guard — SwiftBar plugin (refreshes every 2 min)
# Shows Claude Max usage in macOS menu bar.
# Version: 1.0.0

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
    # SwiftBar syntax: color=light_mode,dark_mode — needed for dark menu bar visibility
    if [[ "$pct" == "?" ]]; then echo "gray,#8e8e93"; return; fi
    if (( pct >= 90 )); then echo "#cc0000,#ff453a"
    elif (( pct >= 70 )); then echo "#cc6600,#ff9f0a"
    elif (( pct >= 60 )); then echo "#996600,#ffd60a"
    else echo "#1a8a1a,#30d158"
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
        echo "1.0|1.0|1.0|now|now"
        return 0
    fi

    if [[ "${http_code:-}" != "200" ]]; then
        log "Unexpected HTTP status: ${http_code:-unknown}"
        return 1
    fi

    local u5 u7 reset5 reset7
    u5=$(echo "$headers" | grep -i "anthropic-ratelimit-unified-5h-utilization" | tr -d '\r' | awk '{print $2}')
    u7=$(echo "$headers" | grep -i "anthropic-ratelimit-unified-7d-utilization" | tr -d '\r' | awk '{print $2}')
    reset5=$(echo "$headers" | grep -i "anthropic-ratelimit-unified-5h-reset" | tr -d '\r' | awk '{print $2}')
    reset7=$(echo "$headers" | grep -i "anthropic-ratelimit-unified-7d-reset" | tr -d '\r' | awk '{print $2}')

    # Validate extracted values
    if ! is_number "${u5:-}" && ! is_number "${u7:-}"; then
        log "No valid utilization headers found (u5='${u5:-}', u7='${u7:-}')"
        return 1
    fi

    # Default invalid values to 0
    is_number "${u5:-}" || u5="0"
    is_number "${u7:-}" || u7="0"

    # Single python call for reset time formatting (pass values via sys.argv, not interpolation)
    python3 - "$u5" "$u7" "${reset5:-0}" "${reset7:-0}" <<'PYEOF'
import sys
from datetime import datetime, timezone

u5 = float(sys.argv[1])
u7 = float(sys.argv[2])
reset5_raw = sys.argv[3]
reset7_raw = sys.argv[4]
max_u = max(u5, u7)

def fmt_reset(ts):
    if not ts or ts == '0':
        return '?'
    try:
        delta = int(ts) - datetime.now(timezone.utc).timestamp()
        if delta <= 0:
            return 'now'
        h = int(delta) // 3600
        m = (int(delta) % 3600) // 60
        return f'{h}h {m}m' if h > 0 else f'{m}m'
    except (ValueError, TypeError):
        return '?'

print(f'{u5}|{u7}|{max_u}|{fmt_reset(reset5_raw)}|{fmt_reset(reset7_raw)}')
PYEOF
}

# --- Fetch data ---
PARSED=$(get_usage_from_headers)
if [[ $? -eq 0 && -n "${PARSED:-}" ]]; then
    U5=$(echo "$PARSED" | cut -d'|' -f1)
    U7=$(echo "$PARSED" | cut -d'|' -f2)
    MAX_U=$(echo "$PARSED" | cut -d'|' -f3)
    R5=$(echo "$PARSED" | cut -d'|' -f4)
    R7=$(echo "$PARSED" | cut -d'|' -f5)

    # Update cache with timestamp and secure permissions
    python3 - "$MAX_U" "$U5" "$U7" "$R5" "$CACHE_FILE" <<'PYEOF'
import json, sys
from datetime import datetime, timezone
max_u, u5, u7, r5, cache_path = float(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3]), sys.argv[4], sys.argv[5]
import os
fd = os.open(cache_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, 'w') as f:
    json.dump({'max_util': max_u, 'five_hour': u5, 'seven_day': u7, 'remaining': r5, 'updated_at': datetime.now(timezone.utc).isoformat()}, f)
PYEOF
    log "Cache updated: u5=$U5 u7=$U7"
else
    # API failed — try reading existing cache
    if [[ -f "$CACHE_FILE" ]]; then
        CACHED=$(python3 - "$CACHE_FILE" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
u5=d.get('five_hour',0); u7=d.get('seven_day',0); mx=d.get('max_util',0); r=d.get('remaining','?'); t=d.get('updated_at','?')
print(f'{u5}|{u7}|{mx}|{r}|{r}|{t}')
PYEOF
        )
        U5=$(echo "$CACHED" | cut -d'|' -f1)
        U7=$(echo "$CACHED" | cut -d'|' -f2)
        MAX_U=$(echo "$CACHED" | cut -d'|' -f3)
        R5=$(echo "$CACHED" | cut -d'|' -f4)
        R7=$(echo "$CACHED" | cut -d'|' -f5)
        CACHE_AGE=$(echo "$CACHED" | cut -d'|' -f6)
        log "Using cached data from $CACHE_AGE"
    else
        MAX_U="?"
        U5="?"
        U7="?"
        R5="?"
        R7="?"
        log "No cache available, showing '?'"
    fi
fi

# --- Format percentages ---
U5_PCT=$(fmt_pct "${U5:-?}")
U7_PCT=$(fmt_pct "${U7:-?}")

# --- Determine max percentage for color ---
if [[ "$U5_PCT" != "?" && "$U7_PCT" != "?" ]]; then
    MAX_PCT=$(( U5_PCT > U7_PCT ? U5_PCT : U7_PCT ))
else
    MAX_PCT="?"
fi

COLOR=$(get_color "$MAX_PCT")

# --- Send notifications if thresholds are crossed ---
if [[ "$MAX_PCT" != "?" ]]; then
    notify_threshold "$MAX_PCT" "$NOTIFY_WARN" "Warning (${NOTIFY_WARN}%)"
    notify_threshold "$MAX_PCT" "$NOTIFY_CRIT" "Critical (${NOTIFY_CRIT}%)"
fi

# --- Menu bar title ---
if [[ "$MAX_U" == "?" ]]; then
    echo "CC: ? | size=13 color=gray"
else
    echo "CC: ${U5_PCT}% / ${U7_PCT}% | size=13 color=$COLOR"
fi

echo "---"

# --- Usage details ---
echo "5h window: ${U5_PCT}% (reset ${R5}) | size=12"
echo "7d window: ${U7_PCT}% (reset ${R7}) | size=12"

echo "---"

# --- Actions ---
echo "Open Anthropic Console | href=https://console.anthropic.com/settings/usage"
echo "Refresh | refresh=true"

if [[ "$DEBUG" == "1" ]]; then
    echo "---"
    echo "Debug mode ON | size=10 color=gray"
    echo "Log: $LOG_FILE | size=10 color=gray"
fi
