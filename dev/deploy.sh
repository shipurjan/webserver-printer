#!/bin/zsh
set -e

# Load zsh config to get SSH aliases (for 1Password/WSL integration)
[[ -f ~/.zshrc ]] && source ~/.zshrc

# Get script directory
SCRIPT_DIR="${0:A:h}"
ROOT_DIR="$SCRIPT_DIR/.."

# Load and validate
[ ! -f "$SCRIPT_DIR/.env" ] && echo "Error: .env not found. Run: cd dev && cp default.env .env && vim .env" && exit 1
source "$SCRIPT_DIR/.env"
[ -z "$HETZNER_API_TOKEN" ] && echo "Error: HETZNER_API_TOKEN not set" && exit 1
[ -z "$SSH_KEY" ] && echo "Error: SSH_KEY not set" && exit 1

# Server configuration
SERVER_TYPE="cx23"       # 2 vCPU, 4GB RAM, 40GB disk
LOCATION="fsn1"          # Falkenstein, Germany
IMAGE="debian-13"        # Debian 13
SERVER_NAME="vps-webhost-init"

# Parse command line parameters
BRANCH="master"
STAGING_MODE=false
REBOOT_AFTER=false
USER_CONFIG_ARG=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --branch)
      BRANCH="$2"
      shift 2
      ;;
    --staging)
      STAGING_MODE=true
      shift
      ;;
    --reboot)
      REBOOT_AFTER=true
      shift
      ;;
    *)
      [ -z "$USER_CONFIG_ARG" ] && USER_CONFIG_ARG="$1"
      shift
      ;;
  esac
done

# Use command line arg if provided, otherwise use deploy.conf from dev/
USER_CONFIG="${USER_CONFIG_ARG:-$SCRIPT_DIR/deploy.conf}"

if [ ! -f "$USER_CONFIG" ]; then
  echo "Error: Config not found: $USER_CONFIG"
  echo "Create one: cd dev && cp ../default.conf deploy.conf && vim deploy.conf"
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
SERVER_IPV4=$(echo "$RESPONSE" | jq -r '.server.public_net.ipv4.ip')
SERVER_IPV6=$(echo "$RESPONSE" | jq -r '.server.public_net.ipv6.ip' | sed 's|/64$||')
echo "Server created: $SERVER_IPV4"

# Extract DOMAIN from config before modifying
DOMAIN=$(grep '^DOMAIN=' "$USER_CONFIG" | cut -d= -f2 | tr -d '"')

# Configure DNS if not using example.com
if [ "$DOMAIN" != "example.com" ]; then
  echo "Configuring DNS for $DOMAIN..."

  # Delete existing zone if it exists
  ZONE_ID=$(curl -s -H "Authorization: Bearer $HETZNER_API_TOKEN" https://api.hetzner.cloud/v1/zones | jq -r ".zones[] | select(.name==\"$DOMAIN\") | .id")
  if [ -n "$ZONE_ID" ]; then
    echo "  Deleting existing DNS zone..."
    curl -s -X DELETE -H "Authorization: Bearer $HETZNER_API_TOKEN" https://api.hetzner.cloud/v1/zones/$ZONE_ID
    sleep 2
  fi

  # Create new zone with records
  echo "  Creating DNS zone with records..."
  ZONE_RESPONSE=$(curl -s -X POST -H "Authorization: Bearer $HETZNER_API_TOKEN" -H "Content-Type: application/json" \
    -d "{
      \"name\": \"$DOMAIN\",
      \"mode\": \"primary\",
      \"ttl\": 3600,
      \"rrsets\": [
        {
          \"name\": \"@\",
          \"type\": \"A\",
          \"ttl\": 3600,
          \"records\": [{\"value\": \"$SERVER_IPV4\"}]
        },
        {
          \"name\": \"*\",
          \"type\": \"A\",
          \"ttl\": 3600,
          \"records\": [{\"value\": \"$SERVER_IPV4\"}]
        },
        {
          \"name\": \"@\",
          \"type\": \"AAAA\",
          \"ttl\": 3600,
          \"records\": [{\"value\": \"$SERVER_IPV6\"}]
        },
        {
          \"name\": \"*\",
          \"type\": \"AAAA\",
          \"ttl\": 3600,
          \"records\": [{\"value\": \"$SERVER_IPV6\"}]
        }
      ]
    }" \
    https://api.hetzner.cloud/v1/zones)

  echo "  DNS configured: $DOMAIN -> $SERVER_IPV4"
  TEMP_CONFIG=""
else
  # Use example.com - set DOMAIN to server IP
  echo "Using example.com - setting DOMAIN to $SERVER_IPV4"
  TEMP_CONFIG=$(mktemp)
  sed "s/^DOMAIN=.*/DOMAIN=\"$SERVER_IPV4\"/" "$USER_CONFIG" > "$TEMP_CONFIG"
  USER_CONFIG="$TEMP_CONFIG"
fi

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
  if ssh -o ConnectTimeout=5 $SSH_OPTS[@] root@$SERVER_IPV4 exit 2>&1; then
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
scp -q $SSH_OPTS[@] "$ROOT_DIR/init.sh" "$USER_CONFIG" root@$SERVER_IPV4:/root/

# Run init
INIT_FLAGS=""
[ "$STAGING_MODE" = true ] && INIT_FLAGS="$INIT_FLAGS --staging"
[ "$REBOOT_AFTER" = true ] && INIT_FLAGS="$INIT_FLAGS --reboot"

echo "Running init script (branch: $BRANCH)..."
ssh $SSH_OPTS[@] root@$SERVER_IPV4 "bash /root/init.sh $INIT_FLAGS /root/$(basename "$USER_CONFIG") $BRANCH"

echo ""
echo "Deployment complete!"
echo "Connect: ssh root@$SERVER_IPV4"
if [ "$DOMAIN" != "example.com" ]; then
  echo "Domain:  https://$DOMAIN (DNS: $SERVER_IPV4)"
fi
echo "Delete:  curl -X DELETE -H \"Authorization: Bearer \$HETZNER_API_TOKEN\" https://api.hetzner.cloud/v1/servers/$SERVER_ID"

# Cleanup
[ -f "$TEMP_CONFIG" ] && rm -f "$TEMP_CONFIG"
