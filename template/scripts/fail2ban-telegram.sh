#!/bin/bash
# fail2ban Telegram notification script
# Called by fail2ban when an IP is banned
# Sends SILENT notifications (disable_notification=true)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../docker/.env"

if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
fi

if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
  exit 0
fi

JAIL="${1:-unknown}"
IP="${2:-unknown}"

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TELEGRAM_CHAT_ID}" \
  -d "parse_mode=HTML" \
  -d "disable_notification=true" \
  -d "text=<b>Ban:</b> <code>$IP</code> ($JAIL)" > /dev/null
