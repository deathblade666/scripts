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

if [ "$DRY_RUN" = true ]; then
    echo "--- RUNNING IN DRY RUN MODE ---"
fi

# Build syncPairs.json dynamically from sync_pairs.conf
JSON_FILE="$FILEN_CLI_DATA_DIR/syncPairs.json"
echo "[" > "$JSON_FILE"

FIRST=true
LOCAL_PATHS=()

while IFS='|' read -r local_path remote_path ignore_file sync_mode exclude_dots <&3; do
    [[ "$local_path" =~ ^#.*$ ]] || [[ -z "$local_path" ]] && continue

    local_path=$(echo "$local_path" | xargs)
    remote_path=$(echo "$remote_path" | xargs)
    ignore_file=$(echo "$ignore_file" | xargs)
    sync_mode=$(echo "$sync_mode" | xargs)
    exclude_dots=$(echo "$exclude_dots" | xargs)

    # Keep track of local paths for cleanup later
    LOCAL_PATHS+=("$local_path")

    # Format ignore patterns into a JSON array if the ignore file exists
    IGNORE_JSON="[]"
    if [ -n "$ignore_file" ] && [ -f "$ignore_file" ]; then
        IGNORE_JSON=$(jq -Rn '[inputs | select(length > 0 and test("^#") | not)]' "$ignore_file" 2>/dev/null || echo "[]")
    fi

    # Determine excludeDotFiles boolean (defaults to true if empty or invalid)
    EXCLUDE_DOTS_BOOL=true
    if [[ "$exclude_dots" =~ ^(false|0|no)$ ]]; then
        EXCLUDE_DOTS_BOOL=false
    fi

    # Construct the JSON object for this pair (defaults to localToCloud if sync_mode is empty)
    PAIR_JSON=$(jq -n \
        --arg loc "$local_path" \
        --arg rem "$remote_path" \
        --argjson ign "$IGNORE_JSON" \
        --arg mode "${sync_mode:-localToCloud}" \
        --argjson exDots "$EXCLUDE_DOTS_BOOL" \
        '{local: $loc, remote: $rem, syncMode: $mode, ignore: $ign, excludeDotFiles: $exDots}')

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
    echo "Would execute: /usr/local/bin/filen sync --skip-update"
    echo "--- DRY RUN COMPLETE ---"
    exit 0
fi

# Execute the central registry sync and capture output/exit code
echo "[$(date)] Starting Filen sync"
HAS_ERROR=false
SYNC_OUTPUT=""
SYNC_EXIT_CODE=0

SYNC_OUTPUT=$(/usr/local/bin/filen sync --skip-update < /dev/null 2>&1)
SYNC_EXIT_CODE=$?

if [ $SYNC_EXIT_CODE -ne 0 ]; then
    echo "[ERROR] Filen sync encountered an error (Exit code: $SYNC_EXIT_CODE)."
    HAS_ERROR=true
fi

# Clean up .filenignore for all configured local paths
for path in "${LOCAL_PATHS[@]}"; do
    rm -f "$path/.filenignore"
done

# Send Discord Webhook Notification
if [ -n "$DISCORD_WEBHOOK_URL" ] && [ "$DISCORD_WEBHOOK_URL" != "YOUR_WEBHOOK_URL_HERE" ]; then
    TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    if [ "$HAS_ERROR" = true ]; then
        if [ ${#SYNC_OUTPUT} -gt 1000 ]; then
            SYNC_OUTPUT="${SYNC_OUTPUT:0:1000}..."
        fi

        payload=$(jq -n \
            --arg title "❌ Filen Sync Failed" \
            --arg desc "One or more sync pairs encountered an error during execution. (Exit Code: $SYNC_EXIT_CODE)" \
            --arg output "$SYNC_OUTPUT" \
            --arg ts "$TIMESTAMP" \
            '{
              embeds: [{
                title: $title,
                description: $desc,
                color: 15158332,
                fields: [
                  {
                    name: "Error Output",
                    value: ("```\n" + ($output // "No output captured") + "\n```")
                  }
                ],
                timestamp: $ts
              }]
            }')
    else
        # Build an array of paths for jq to format properly
        # Pass the bash array into a JSON array using jq -R and --slurpfile, or map them dynamically
        SYNCED_ARRAY=$(printf '%s\n' "${LOCAL_PATHS[@]}" | jq -R . | jq -s .)

        payload=$(jq -n \
            --arg title "✅ Filen Sync Successful" \
            --arg desc "All sync pairs processed successfully." \
            --argjson paths "$SYNCED_ARRAY" \
            --arg ts "$TIMESTAMP" \
            '
            ($paths // [] | map("- `" + . + "`") | join("\n")) as $list
            | {
              embeds: [{
                title: $title,
                description: $desc,
                color: 3066993,
                fields: [
                  {
                    name: "Synced Local Paths",
                    value: ($list | if . == "" then "No paths found" else . end)
                  }
                ],
                timestamp: $ts
              }]
            }' )
    fi

    curl -H "Content-Type: application/json" -X POST -d "$payload" "$DISCORD_WEBHOOK_URL" >/dev/null 2>&1
fi