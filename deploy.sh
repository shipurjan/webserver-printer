#!/bin/zsh
set -e

# Load zsh config to get SSH aliases (for 1Password/WSL integration)
[[ -f ~/.zshrc ]] && source ~/.zshrc

# Load and validate
[ ! -f .env ] && echo "Error: .env not found. Run: cp default.env .env && nano .env" && exit 1
source .env
[ -z "$HETZNER_API_TOKEN" ] && echo "Error: HETZNER_API_TOKEN not set" && exit 1
[ -z "$SSH_KEY" ] && echo "Error: SSH_KEY not set" && exit 1

# Defaults
SERVER_TYPE=${SERVER_TYPE:-cx23}
LOCATION=${LOCATION:-nbg1}
IMAGE=${IMAGE:-debian-13}
SERVER_NAME=${SERVER_NAME:-vps-webhost-init}

# Use command line arg if provided, otherwise use deploy.conf
USER_CONFIG="${1:-deploy.conf}"

if [ ! -f "$USER_CONFIG" ]; then
  echo "Error: Config not found: $USER_CONFIG"
  echo "Create one: cp default.conf deploy.conf && vim deploy.conf"
  exit 1
fi

# SSH options (use array for proper expansion in zsh)
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

# Check for existing server with same name
echo "Checking for existing server..."
EXISTING=$(curl -s -H "Authorization: Bearer $HETZNER_API_TOKEN" https://api.hetzner.cloud/v1/servers | jq -r ".servers[] | select(.name==\"$SERVER_NAME\") | .id")

if [ -n "$EXISTING" ]; then
  echo "Deleting existing server (ID: $EXISTING)..."
  curl -s -X DELETE -H "Authorization: Bearer $HETZNER_API_TOKEN" https://api.hetzner.cloud/v1/servers/$EXISTING
  sleep 2
fi

# Create server
echo "Creating server $SERVER_NAME..."
RESPONSE=$(curl -s -X POST -H "Authorization: Bearer $HETZNER_API_TOKEN" -H "Content-Type: application/json" \
  -d "{\"name\":\"$SERVER_NAME\",\"server_type\":\"$SERVER_TYPE\",\"location\":\"$LOCATION\",\"image\":\"$IMAGE\",\"ssh_keys\":[\"$SSH_KEY\"],\"start_after_create\":true}" \
  https://api.hetzner.cloud/v1/servers)

echo "$RESPONSE" | jq -e '.error' >/dev/null 2>&1 && echo "Error: $(echo "$RESPONSE" | jq -r '.error.message')" && exit 1

SERVER_ID=$(echo "$RESPONSE" | jq -r '.server.id')
SERVER_IP=$(echo "$RESPONSE" | jq -r '.server.public_net.ipv4.ip')
echo "Server created: $SERVER_IP"

# Update DOMAIN in config to use server IP
TEMP_CONFIG=$(mktemp)
sed "s/^DOMAIN=.*/DOMAIN=\"$SERVER_IP\"/" "$USER_CONFIG" > "$TEMP_CONFIG"
USER_CONFIG="$TEMP_CONFIG"

# Wait for running status
echo "Waiting for server..."
while true; do
  STATUS=$(curl -s -H "Authorization: Bearer $HETZNER_API_TOKEN" https://api.hetzner.cloud/v1/servers/$SERVER_ID | jq -r '.server.status')
  [ "$STATUS" = "running" ] && break
  echo "  Status: $STATUS"
  sleep 5
done

# Wait for SSH
echo "Waiting for SSH..."
echo "  Checking SSH keys in agent..."
ssh-add -l 2>/dev/null || echo "  Warning: No keys in ssh-agent"

for i in {1..30}; do
  echo "  Attempt $i/30"
  if ssh -o ConnectTimeout=5 $SSH_OPTS[@] root@$SERVER_IP exit 2>&1; then
    break
  else
    SSH_ERROR=$?
    echo "    (Connection failed with code: $SSH_ERROR)"
  fi
  [ $i -eq 30 ] && echo "Error: SSH timeout" && exit 1
  sleep 5
done

# Copy files
echo "Copying files..."
scp -q $SSH_OPTS[@] init.sh "$USER_CONFIG" root@$SERVER_IP:/root/

# Run init
echo "Running init script..."
ssh $SSH_OPTS[@] root@$SERVER_IP "bash /root/init.sh /root/$(basename "$USER_CONFIG")"

echo ""
echo "Deployment complete!"
echo "Connect: ssh root@$SERVER_IP"
echo "Delete:  curl -X DELETE -H \"Authorization: Bearer \$HETZNER_API_TOKEN\" https://api.hetzner.cloud/v1/servers/$SERVER_ID"

# Cleanup
rm -f "$TEMP_CONFIG"
