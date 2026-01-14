#!/bin/bash
# Reboot notification script
# Sends Telegram notification when system reboot is required after security updates
# Run via cron: 0 7 * * * /root/__#TEMPLATE#:DOMAIN__/scripts/reboot-notify.sh

STATE_FILE="/tmp/reboot-notify-state"
SCRIPT_DIR="$(dirname "$0")"

# Source DOMAIN from .env
ENV_FILE="$SCRIPT_DIR/../docker/.env"
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
fi

# Check if reboot is required
if [ -f /var/run/reboot-required ]; then
  # Get modification time of reboot-required file to track state
  REBOOT_STATE=$(stat -c %Y /var/run/reboot-required 2>/dev/null)

  # Check if we already notified about this reboot requirement
  if grep -Fxq "$REBOOT_STATE" "$STATE_FILE" 2>/dev/null; then
    exit 0
  fi

  # Get packages that triggered the reboot requirement
  PACKAGES=""
  if [ -f /var/run/reboot-required.pkgs ]; then
    PACKAGES=$(cat /var/run/reboot-required.pkgs | tr '\n' ', ' | sed 's/, $//')
  fi

  # Send Telegram notification
  "$SCRIPT_DIR/telegram-notify.sh" "Reboot Required - $DOMAIN" \
"A system reboot is required after security updates.

<b>Packages:</b> <code>${PACKAGES:-unknown}</code>

To reboot: <code>reboot</code>

Docker containers will auto-restart after reboot."

  # Save state to avoid duplicate notifications
  echo "$REBOOT_STATE" > "$STATE_FILE"
else
  # No reboot required, clear state
  > "$STATE_FILE"
fi
