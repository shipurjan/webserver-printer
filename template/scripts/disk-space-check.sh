#!/bin/bash
# Disk space monitoring script
# Sends Telegram alert when disk usage exceeds threshold
# Run via cron: 0 8 * * * /root/__#TEMPLATE#:DOMAIN__/scripts/disk-space-check.sh

THRESHOLD=80
DOMAIN="__#TEMPLATE#:DOMAIN__"
SCRIPT_DIR="$(dirname "$0")"

# Get current disk usage percentage
USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')

if [ "$USAGE" -gt "$THRESHOLD" ]; then
  DISK_INFO=$(df -h / | tail -1)

  "$SCRIPT_DIR/telegram-notify.sh" "💾 Disk Space Warning - $DOMAIN" \
"Disk usage has exceeded <b>${THRESHOLD}%</b> threshold.

Current usage: <b>${USAGE}%</b>

<code>$DISK_INFO</code>

To free up space:
• <code>docker system prune -af --volumes</code>
• <code>apt clean</code>"
fi
