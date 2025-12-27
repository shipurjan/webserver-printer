#!/bin/bash
# Telegram notification helper script
# Usage: echo "message" | telegram-notify.sh "Title"
# Or: telegram-notify.sh "Title" "Message"

BOT_TOKEN="__#TEMPLATE#:TELEGRAM_BOT_TOKEN__"
CHAT_ID="__#TEMPLATE#:TELEGRAM_CHAT_ID__"

# Exit if Telegram not configured
if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
  exit 0
fi

TITLE="$1"
MESSAGE="${2:-$(cat)}"

# Format message with title
TEXT="<b>$TITLE</b>

$MESSAGE"

# Send via Telegram Bot API
curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d "chat_id=${CHAT_ID}" \
  -d "parse_mode=HTML" \
  -d "text=${TEXT}" > /dev/null
