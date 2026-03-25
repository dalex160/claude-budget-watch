#!/bin/bash
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideSwiftBar>false</swiftbar.hideSwiftBar>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
#
# Budget Guard — SwiftBar plugin (refreshes every 2 min)
# Shows Claude Max usage in macOS menu bar.

CACHE_FILE="$HOME/.claude/budget-cache.json"

# --- Get fresh usage from rate-limit headers ---
get_usage_from_headers() {
    local token
    token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])" 2>/dev/null)

    if [[ -z "$token" ]]; then
        return 1
    fi

    local headers
    headers=$(curl -s -D - -o /dev/null --max-time 15 \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -H "anthropic-version: 2023-06-01" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -X POST "https://api.anthropic.com/v1/messages" \
        -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"h"}]}' 2>/dev/null)

    if [[ -z "$headers" ]]; then
        return 1
    fi

    local u5 u7 reset5 reset7
    u5=$(echo "$headers" | grep -i "anthropic-ratelimit-unified-5h-utilization" | tr -d '\r' | awk '{print $2}')
    u7=$(echo "$headers" | grep -i "anthropic-ratelimit-unified-7d-utilization" | tr -d '\r' | awk '{print $2}')
    reset5=$(echo "$headers" | grep -i "anthropic-ratelimit-unified-5h-reset" | tr -d '\r' | awk '{print $2}')
    reset7=$(echo "$headers" | grep -i "anthropic-ratelimit-unified-7d-reset" | tr -d '\r' | awk '{print $2}')

    if [[ -z "$u5" && -z "$u7" ]]; then
        return 1
    fi

    python3 -c "
from datetime import datetime, timezone
u5 = float('${u5:-0}')
u7 = float('${u7:-0}')
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
    except:
        return '?'

print(f'{u5}|{u7}|{max_u}|{fmt_reset(\"${reset5:-0}\")}|{fmt_reset(\"${reset7:-0}\")}')
" 2>/dev/null
}

# --- Fetch data ---
PARSED=$(get_usage_from_headers)
if [[ $? -eq 0 && -n "$PARSED" ]]; then
    U5=$(echo "$PARSED" | cut -d'|' -f1)
    U7=$(echo "$PARSED" | cut -d'|' -f2)
    MAX_U=$(echo "$PARSED" | cut -d'|' -f3)
    R5=$(echo "$PARSED" | cut -d'|' -f4)
    R7=$(echo "$PARSED" | cut -d'|' -f5)

    # Update cache
    python3 -c "
import json
max_u = float('$MAX_U')
u5 = float('$U5')
u7 = float('$U7')
json.dump({'max_util': max_u, 'five_hour': u5, 'seven_day': u7, 'remaining': '$R5'}, open('$CACHE_FILE', 'w'))
" 2>/dev/null
else
    # API failed — try reading existing cache
    if [[ -f "$CACHE_FILE" ]]; then
        CACHED=$(python3 -c "
import json
d = json.load(open('$CACHE_FILE'))
u5=d.get('five_hour',0); u7=d.get('seven_day',0); mx=d.get('max_util',0); r=d.get('remaining','?')
print(f'{u5}|{u7}|{mx}|{r}|{r}')
" 2>/dev/null)
        U5=$(echo "$CACHED" | cut -d'|' -f1)
        U7=$(echo "$CACHED" | cut -d'|' -f2)
        MAX_U=$(echo "$CACHED" | cut -d'|' -f3)
        R5=$(echo "$CACHED" | cut -d'|' -f4)
        R7=$(echo "$CACHED" | cut -d'|' -f5)
    else
        MAX_U="?"
        U5="?"
        U7="?"
        R5="?"
        R7="?"
    fi
fi

# --- Convert 0.0-1.0 to percentage ---
fmt_pct() {
    python3 -c "v=float('$1'); print(f'{v*100:.0f}' if v<=1 else f'{v:.0f}')" 2>/dev/null || echo "?"
}

U5_PCT=$(fmt_pct "$U5")
U7_PCT=$(fmt_pct "$U7")

# --- Menu bar title ---
if [[ "$MAX_U" == "?" ]]; then
    echo "CC: ? | size=13"
else
    echo "CC: ${U5_PCT}% / ${U7_PCT}% | size=13"
fi

echo "---"

# --- Usage details ---
echo "5h window: ${U5_PCT}% (reset ${R5}) | size=12"
echo "7d window: ${U7_PCT}% (reset ${R7}) | size=12"
