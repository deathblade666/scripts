#!/bin/bash
cd "$(dirname "$0")"
export FILEN_CLI_DATA_DIR="$(pwd)/data"

# --- CONFIGURATION ---
DISCORD_WEBHOOK_URL=""
# ---------------------

DRY_RUN=false
for arg in "$@"; do
    if [ "$arg" == "--dry-run" ]; then
        DRY_RUN=true
        break
    fi
done

if [ "$DRY_RUN" = false ]; then
    if [ ! -d "$FILEN_CLI_DATA_DIR" ] || [ -z "$(ls -A "$FILEN_CLI_DATA_DIR" 2>/dev/null)" ]; then
        echo "No Filen credentials detected in the local data directory."
        echo "Please log in to link your account:"
        filen login
        echo ""
    fi
else
    echo "--- RUNNING IN DRY RUN MODE ---"
fi

# Build syncPairs.json dynamically from sync_pairs.conf
JSON_FILE="$FILEN_CLI_DATA_DIR/syncPairs.json"
echo "[" > "$JSON_FILE"

FIRST=true
LOCAL_PATHS=()

while IFS='|' read -r local_path remote_path ignore_file sync_mode <&3; do
    [[ "$local_path" =~ ^#.*$ ]] || [[ -z "$local_path" ]] && continue

    local_path=$(echo "$local_path" | xargs)
    remote_path=$(echo "$remote_path" | xargs)
    ignore_file=$(echo "$ignore_file" | xargs)
    sync_mode=$(echo "$sync_mode" | xargs)

    # Keep track of local paths for cleanup later
    LOCAL_PATHS+=("$local_path")

    # Format ignore patterns into a JSON array if the ignore file exists
    IGNORE_JSON="[]"
    if [ -n "$ignore_file" ] && [ -f "$ignore_file" ]; then
        IGNORE_JSON=$(jq -Rn '[inputs | select(length > 0 and test("^#") | not)]' "$ignore_file" 2>/dev/null || echo "[]")
    fi

    # Construct the JSON object for this pair (defaults to localToCloud if sync_mode is empty)
    PAIR_JSON=$(jq -n \
        --arg loc "$local_path" \
        --arg rem "$remote_path" \
        --argjson ign "$IGNORE_JSON" \
        --arg mode "${sync_mode:-localToCloud}" \
        '{local: $loc, remote: $rem, syncMode: $mode, ignore: $ign}')

    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        echo "," >> "$JSON_FILE"
    fi
    echo "$PAIR_JSON" >> "$JSON_FILE"

done 3< sync_pairs.conf
echo "]" >> "$JSON_FILE"

if [ "$DRY_RUN" = true ]; then
    echo "--- DRY RUN: Generated syncPairs.json Content ---"
    cat "$JSON_FILE"
    echo "--------------------------------------------------"
    echo "Would execute: filen sync --skip-update"
    echo "--- DRY RUN COMPLETE ---"
    exit 0
fi

# Execute the central registry sync
echo "[$(date)] Starting Filen sync"
HAS_ERROR=false

if ! filen sync --skip-update < /dev/null; then
    echo "[ERROR] Filen sync encountered an error."
    HAS_ERROR=true
fi

# Clean up .filenignore for all configured local paths
for path in "${LOCAL_PATHS[@]}"; do
    rm -f "$path/.filenignore"
done

# Send Discord Webhook Notification
if [ -n "$DISCORD_WEBHOOK_URL" ] && [ "$DISCORD_WEBHOOK_URL" != "YOUR_WEBHOOK_URL_HERE" ]; then
    if [ "$HAS_ERROR" = true ]; then
        payload=$(cat <<EOF
{
  "embeds": [{
    "title": "❌ Filen Sync Failed",
    "description": "One or more sync pairs encountered an error during execution.",
    "color": 15158332,
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }]
}
EOF
)
    else
        payload=$(cat <<EOF
{
  "embeds": [{
    "title": "✅ Filen Sync Successful",
    "description": "All sync pairs processed successfully.",
    "color": 3066993,
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }]
}
EOF
)
    fi

    curl -H "Content-Type: application/json" -X POST -d "$payload" "$DISCORD_WEBHOOK_URL" >/dev/null 2>&1
fi

