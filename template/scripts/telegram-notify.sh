#!/bin/bash
# Telegram notification helper script
# Usage: telegram-notify.sh "Title" "Message"
# Or: echo "message" | telegram-notify.sh "Title"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../docker/.env"

if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
fi

if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
  exit 0
fi

TITLE="$1"
MESSAGE="${2:-$(cat)}"

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TELEGRAM_CHAT_ID}" \
  -d "parse_mode=HTML" \
  -d "text=<b>$TITLE</b>

$MESSAGE" > /dev/null
