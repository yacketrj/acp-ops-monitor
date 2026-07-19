#!/usr/bin/env bash
# notify-discord.sh — Post development events to Discord #acp-updates channel.
# Usage: notify-discord.sh <event> <title> <description> [url] [color]
# Events: branch-created, pr-created, pr-merged, upstream-pr-created, upstream-pr-merged

set -euo pipefail

WEBHOOK_URL="${DISCORD_DEV_WEBHOOK_URL:-}"
WEBHOOK_FILE="${HOME}/dune-docker-addon/e2e-integration/secrets/dev-webhook-url.txt"

if [ -z "$WEBHOOK_URL" ] && [ -f "$WEBHOOK_FILE" ]; then
  WEBHOOK_URL="$(tr -d '\r\n' < "$WEBHOOK_FILE")"
fi

if [ -z "$WEBHOOK_URL" ]; then
  echo "No Discord webhook URL found. Set DISCORD_DEV_WEBHOOK_URL or create $WEBHOOK_FILE" >&2
  exit 0
fi

EVENT="${1:-}"
TITLE="${2:-}"
DESC="${3:-}"
URL="${4:-}"
COLOR="${5:-}"

if [ -z "$EVENT" ] || [ -z "$TITLE" ]; then
  echo "Usage: notify-discord.sh <event> <title> [description] [url] [color]" >&2
  exit 1
fi

case "$EVENT" in
  branch-created)      COLOR="5814783"  ;; # purple
  pr-created)          COLOR="3447003"  ;; # blue
  pr-merged)           COLOR="3066993"  ;; # green
  upstream-pr-created) COLOR="15105570" ;; # orange
  upstream-pr-merged)  COLOR="3066993"  ;; # green
  deploy)              COLOR="10181046" ;; # red
  *)                   COLOR="${5:-0}"   ;;
esac

# Convert literal \n in description to actual newlines
DESC=$(printf '%b' "$DESC")

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

PAYLOAD=$(python3 -c "
import json, sys
payload = {
    'username': 'ACP Dev Bot',
    'avatar_url': 'https://cdn.discordapp.com/attachments/1521604431622311966/1521604431995474111/0f77d5a4-7f75-4e33-993c-ffd61cd7712f.png',
    'embeds': [{
        'title': sys.argv[1],
        'description': sys.argv[2],
        'url': sys.argv[3] if sys.argv[3] else None,
        'color': int(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[4] else 0,
        'timestamp': '$TIMESTAMP',
        'footer': {'text': 'ACP Development Pipeline'}
    }]
}
print(json.dumps(payload))
" "$TITLE" "$DESC" "${URL:-}" "${COLOR:-0}" 2>/dev/null)

if [ -z "$PAYLOAD" ]; then
  echo "Failed to build JSON payload" >&2
  exit 0
fi

curl -fsS -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" >/dev/null 2>&1 || true

echo "Discord notification sent: $EVENT — $TITLE"
