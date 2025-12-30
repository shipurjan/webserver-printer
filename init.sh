#!/bin/bash
set -e

# Prevent interactive prompts during package installation
export DEBIAN_FRONTEND=noninteractive

# Script version
VERSION="0.0.2"

# Pinned versions
OHMYZSH_COMMIT="92aed2e93624124182ba977a91efa5bbe1e76d5f"
ZSH_AUTOSUGGESTIONS_COMMIT="85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5"
POWERLEVEL10K_COMMIT="36f3045d69d1ba402db09d09eb12b42eebe0fa3b"
LAZYDOCKER_COMMIT="78edbf3d2e3bb79440bdb88f4382cab9f81c43e4"
TPM_COMMIT="99469c4a9b1ccf77fade25842dc7bafbc8ce9946"

# Default config URL
DEFAULT_CONFIG_URL="https://raw.githubusercontent.com/shipurjan/webserver-printer/refs/heads/master/default.conf"

# Parse command line arguments
USER_CONFIG_SOURCE=""
BRANCH="master"
STAGING_MODE=false
REBOOT_AFTER=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --staging)
      STAGING_MODE=true
      shift
      ;;
    --reboot)
      REBOOT_AFTER=true
      shift
      ;;
    *)
      if [ -z "$USER_CONFIG_SOURCE" ]; then
        USER_CONFIG_SOURCE="$1"
      else
        BRANCH="$1"
      fi
      shift
      ;;
  esac
done

# Require config file
if [ -z "$USER_CONFIG_SOURCE" ]; then
  echo "Error: Config file path is required"
  echo "Usage: $0 [--staging] [--reboot] <config-file> [branch]"
  exit 1
fi

apt update

# Configure locales early to suppress perl warnings
echo "=== Configuring locales ==="
apt install -y locales
sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen

# Unset broken locale variables from SSH client and set proper ones
unset LC_CTYPE
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

locale-gen
update-locale LANG=en_US.UTF-8

# Install curl (needed for downloading config)
echo "=== Installing curl ==="
apt install -y curl

# Load default configuration
CONFIG_FILE="/root/setup-config.sh"
echo "=== Loading default configuration (branch: $BRANCH) ==="
curl -fsSL "https://raw.githubusercontent.com/shipurjan/webserver-printer/refs/heads/$BRANCH/default.conf" -o "$CONFIG_FILE"

# Load user configuration
echo "=== Loading user configuration ==="
USER_CONFIG_FILE="/root/user-config.sh"

# Check if it's a URL or file path
if [[ "$USER_CONFIG_SOURCE" =~ ^https?:// ]]; then
  # It's a URL, fetch it
  echo "Fetching configuration from URL: $USER_CONFIG_SOURCE"
  curl -fsSL "$USER_CONFIG_SOURCE" -o "$USER_CONFIG_FILE"
elif [ -f "$USER_CONFIG_SOURCE" ]; then
  # It's a file, copy it
  echo "Reading configuration from file: $USER_CONFIG_SOURCE"
  cp "$USER_CONFIG_SOURCE" "$USER_CONFIG_FILE"
else
  echo "Error: Config source not found: $USER_CONFIG_SOURCE"
  exit 1
fi

# Source both files to merge (user config overwrites defaults)
source "$CONFIG_FILE"
source "$USER_CONFIG_FILE"

# Write merged config back
cat >"$CONFIG_FILE" <<EOF
# Merged configuration (defaults + user overrides)

DOMAIN="$DOMAIN"
EMAIL="$EMAIL"
FULL_NAME="$FULL_NAME"
ADMIN_LOGIN="$ADMIN_LOGIN"
ADMIN_PASSWORD="$ADMIN_PASSWORD"
TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"
SSH_PORT="$SSH_PORT"
GITHUB_REPO_URL="$GITHUB_REPO_URL"
EOF

rm -f "$USER_CONFIG_FILE"

# Source the final configuration
source "$CONFIG_FILE"

# Sanitize domain for use in file names and SSH config
DOMAIN_SANITIZED=$(echo "$DOMAIN" | sed 's/[^a-zA-Z0-9_]/_/g')

echo "=== Configuration loaded ==="
echo "Domain: $DOMAIN"
echo "Email: $EMAIL"

echo "=== Updating system ==="
apt update
apt upgrade -y

echo "=== Installing essential packages ==="
apt install -y \
  curl \
  wget \
  git \
  tmux \
  ufw \
  fail2ban \
  ca-certificates \
  gnupg \
  gawk \
  perl \
  grep \
  sed \
  ripgrep \
  fd-find \
  whois \
  tree \
  vim \
  jq \
  xsel

# Create fd symlink (Debian names it fdfind)
mkdir -p /root/.local/bin
ln -s $(which fdfind) /root/.local/bin/fd

# Suppress detached HEAD advice during pinned checkouts
git config --global advice.detachedHead false

echo "=== Hardening SSH configuration ==="

# Create SSH hardening config
cat >/etc/ssh/sshd_config.d/99-hardening.conf <<EOF
# Disable password authentication (key-only)
PasswordAuthentication no
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes

# Root login with keys only
PermitRootLogin prohibit-password
EOF

# Configure custom SSH port if not default
if [ "$SSH_PORT" != "22" ]; then
  echo "Port $SSH_PORT" >/etc/ssh/sshd_config.d/99-custom-port.conf
  echo "  SSH port changed to $SSH_PORT (remember to use -p $SSH_PORT for future connections)"
fi

# Test SSH config before restarting
if ! sshd -t 2>/dev/null; then
  echo "  ERROR: SSH config test failed, reverting changes"
  rm -f /etc/ssh/sshd_config.d/99-hardening.conf /etc/ssh/sshd_config.d/99-custom-port.conf
  exit 1
fi

# Restart SSH to apply changes
systemctl restart sshd
echo "  SSH hardening applied (password auth disabled, key-only)"

echo "=== Installing Docker ==="
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" >/etc/apt/sources.list.d/docker.list

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable Docker to start on boot
systemctl enable docker

# Install lazydocker
curl -fsSL "https://raw.githubusercontent.com/jesseduffield/lazydocker/$LAZYDOCKER_COMMIT/scripts/install_update_linux.sh" | bash

echo "=== Installing Zsh and Oh My Zsh ==="
apt install -y zsh fzf

# Install oh-my-zsh (pinned)
git clone https://github.com/ohmyzsh/ohmyzsh.git /root/.oh-my-zsh
git -C /root/.oh-my-zsh fetch --depth=1 origin $OHMYZSH_COMMIT
git -C /root/.oh-my-zsh checkout $OHMYZSH_COMMIT
cp /root/.oh-my-zsh/templates/zshrc.zsh-template /root/.zshrc

# Install zsh-autosuggestions plugin (pinned)
git clone https://github.com/zsh-users/zsh-autosuggestions /root/.oh-my-zsh/custom/plugins/zsh-autosuggestions
git -C /root/.oh-my-zsh/custom/plugins/zsh-autosuggestions fetch --depth=1 origin $ZSH_AUTOSUGGESTIONS_COMMIT
git -C /root/.oh-my-zsh/custom/plugins/zsh-autosuggestions checkout $ZSH_AUTOSUGGESTIONS_COMMIT

# Detect distro for plugin
DISTRO_PLUGIN="debian"
if grep -qi ubuntu /etc/os-release; then
  DISTRO_PLUGIN="ubuntu"
fi

sed -i "s/plugins=(git)/plugins=(git docker docker-compose sudo fzf colored-man-pages extract history command-not-found ufw $DISTRO_PLUGIN zsh-autosuggestions)/" /root/.zshrc

# Install powerlevel10k theme (pinned)
git clone https://github.com/romkatv/powerlevel10k.git /root/.oh-my-zsh/custom/themes/powerlevel10k
git -C /root/.oh-my-zsh/custom/themes/powerlevel10k fetch --depth=1 origin $POWERLEVEL10K_COMMIT
git -C /root/.oh-my-zsh/custom/themes/powerlevel10k checkout $POWERLEVEL10K_COMMIT
sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="powerlevel10k\/powerlevel10k"/' /root/.zshrc

# Download powerlevel10k config
curl -fsSL "https://raw.githubusercontent.com/shipurjan/webserver-printer/refs/heads/$BRANCH/p10k.zsh" -o /root/.p10k.zsh
echo '[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh' >>/root/.zshrc

# Pre-install gitstatusd for powerlevel10k
/root/.oh-my-zsh/custom/themes/powerlevel10k/gitstatus/install

# Set default editor and PATH
echo "export EDITOR=vim" >>/root/.zshrc
echo 'export PATH="$HOME/.local/bin:$PATH"' >>/root/.zshrc

# Add useful settings and aliases
cat >>/root/.zshrc <<'EOF'

# History timestamps
HIST_STAMPS="yyyy-mm-dd"

# Safety aliases
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Colorful aliases
alias ls='ls --color=auto'
alias ll='ls -l'
alias l='ls -lA'
alias grep='grep --color=auto'
alias diff='diff --color=auto'
EOF

chsh -s $(which zsh)

# Install Tmux Plugin Manager (pinned)
git clone https://github.com/tmux-plugins/tpm /root/.tmux/plugins/tpm
git -C /root/.tmux/plugins/tpm fetch --depth=1 origin $TPM_COMMIT
git -C /root/.tmux/plugins/tpm checkout $TPM_COMMIT

# Create OSC 52 clipboard script for copying over SSH
mkdir -p /root/.local/bin
cat >/root/.local/bin/yank-osc52 <<'EOF'
#!/bin/sh
# Copy to clipboard using OSC 52 escape sequence
# Works over SSH with compatible terminals (iTerm2, Windows Terminal, etc.)

buf=$(cat)

# Tmux requires wrapping in DCS sequence
if [ -n "$TMUX" ]; then
  printf "\033Ptmux;\033\033]52;c;%s\a\033\\" "$(printf %s "$buf" | base64 | tr -d '\n')"
else
  printf "\033]52;c;%s\a" "$(printf %s "$buf" | base64 | tr -d '\n')"
fi
EOF
chmod +x /root/.local/bin/yank-osc52

# Create tmux config with plugins
cat >/root/.tmux.conf <<'EOF'
# Use zsh as default shell
set-option -g default-shell /usr/bin/zsh

# Use vi key bindings in copy mode
setw -g mode-keys vi

# Configure tmux-yank to use OSC 52 for clipboard over SSH
set -g @override_copy_command '$HOME/.local/bin/yank-osc52'

# List of plugins
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'tmux-plugins/tmux-yank'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'
set -g @plugin 'tmux-plugins/tmux-pain-control'
set -g @plugin 'tmux-plugins/tmux-copycat'

# Fix for Windows Terminal escape code issue
# Must be set after tmux-sensible (which sets it to 0)
set -s escape-time 50

# Initialize TMUX plugin manager (keep this line at the very bottom of tmux.conf)
run '~/.tmux/plugins/tpm/tpm'
EOF

# Install tmux plugins
/root/.tmux/plugins/tpm/bin/install_plugins

# Clone repo and scaffold project from template
echo "Cloning template from GitHub (branch: $BRANCH)"
git clone --depth=1 --branch "$BRANCH" https://github.com/shipurjan/webserver-printer.git /tmp/webserver-printer
cp -r /tmp/webserver-printer/template "/root/$DOMAIN"

# Replace placeholders with config values
find "/root/$DOMAIN" -type f -exec sed -i \
  -e "s|__#TEMPLATE#:VERSION__|$VERSION|g" \
  -e "s|__#TEMPLATE#:DOMAIN__|$DOMAIN|g" \
  -e "s|__#TEMPLATE#:EMAIL__|$EMAIL|g" \
  -e "s|__#TEMPLATE#:ADMIN_LOGIN__|$ADMIN_LOGIN|g" \
  -e "s|__#TEMPLATE#:ADMIN_PASSWORD__|$ADMIN_PASSWORD|g" \
  -e "s|__#TEMPLATE#:TELEGRAM_BOT_TOKEN__|${TELEGRAM_BOT_TOKEN:-}|g" \
  -e "s|__#TEMPLATE#:TELEGRAM_CHAT_ID__|${TELEGRAM_CHAT_ID:-}|g" \
  {} \;

# Configure Let's Encrypt staging if requested
if [ "$STAGING_MODE" = true ]; then
  echo "  Using Let's Encrypt STAGING environment (testing mode)"
  sed -i '1 a\	acme_ca https://acme-staging-v02.api.letsencrypt.org/directory' "/root/$DOMAIN/docker/caddy/Caddyfile"
fi

# Make scripts executable
chmod +x "/root/$DOMAIN/scripts/"*.sh

# Generate bcrypt password hash for Caddy basic_auth
ADMIN_PASSWORD_HASH=$(mkpasswd -m bcrypt -R 14 "$ADMIN_PASSWORD")

# Create .env file for docker-compose
cat >"/root/$DOMAIN/docker/.env" <<EOF
DOMAIN='$DOMAIN'
LOGS_USERNAME='$ADMIN_LOGIN'
LOGS_PASSWORD_HASH='$ADMIN_PASSWORD_HASH'
TELEGRAM_BOT_TOKEN='$TELEGRAM_BOT_TOKEN'
TELEGRAM_CHAT_ID='$TELEGRAM_CHAT_ID'
EOF

echo "=== Configuring fail2ban for honeypot protection ==="

# Create Caddy log directory and file (fail2ban needs file to exist)
mkdir -p /var/log/caddy
touch /var/log/caddy/access.log

# Create fail2ban filter for Caddy honeypots
cat >/etc/fail2ban/filter.d/caddy-honeypot.conf <<'EOF'
[Definition]
# Caddy honeypot filter for JSON logs
# Matches any request that triggers the X-Honeypot header

failregex = "remote_ip":"<HOST>".*?"X-Honeypot":\["trapped"\]
            "client_ip":"<HOST>".*?"X-Honeypot":\["trapped"\]

ignoreregex =
EOF

# Create fail2ban action for Docker iptables
cat >/etc/fail2ban/action.d/docker-iptables.conf <<'EOF'
# Fail2Ban action for Docker containers
# Uses DOCKER-USER chain which Docker respects

[Definition]

actionstart = iptables -N f2b-<name>
              iptables -A DOCKER-USER -j f2b-<name>
              iptables -A f2b-<name> -j RETURN

actionstop = iptables -D DOCKER-USER -j f2b-<name>
             iptables -F f2b-<name>
             iptables -X f2b-<name>

actioncheck = iptables -n -L DOCKER-USER | grep -q 'f2b-<name>[ \t]'

actionban = iptables -I f2b-<name> 1 -s <ip> -j REJECT --reject-with icmp-port-unreachable

actionunban = iptables -D f2b-<name> -s <ip> -j REJECT --reject-with icmp-port-unreachable

[Init]
name = default
EOF

# Create fail2ban action for Telegram notifications
cat >/etc/fail2ban/action.d/telegram.conf <<EOF
# Telegram notification action for fail2ban

[Definition]

actionban = /root/$DOMAIN/scripts/fail2ban-telegram.sh <name> <ip>

[Init]
EOF

# Create fail2ban jail configuration
cat >/etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
action = iptables[name=SSH, port=$SSH_PORT, protocol=tcp]
         telegram

[caddy-honeypot]
enabled = true
port = http,https
filter = caddy-honeypot
action = docker-iptables[name=caddy-honeypot]
         telegram
logpath = /var/log/caddy/access.log
maxretry = 1
bantime = 86400
findtime = 600
EOF

# Restart fail2ban to apply configuration
systemctl restart fail2ban
systemctl enable fail2ban

echo "fail2ban configured with honeypot protection"

# Initialize fresh git repo with initial commit
cd "/root/$DOMAIN"
git config --global core.pager ''
git init -b master
git add .
git -c user.email='<>' -c user.name='webserver-printer' commit -m "init (webserver-printer v$VERSION) [skip ci]"

# Set git identity for future commits
git config --global user.email "$EMAIL"
git config --global user.name "$FULL_NAME"

# GitHub integration (optional)
if [ -n "$GITHUB_REPO_URL" ]; then
  echo "=== Setting up GitHub integration ==="

  # Generate deploy keys (RW and RO)
  echo "  Generating deploy keys..."
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh

  ssh-keygen -t ed25519 -f /root/.ssh/${DOMAIN_SANITIZED}_deploy_rw -N "" -C "deploy-rw@$DOMAIN"
  ssh-keygen -t ed25519 -f /root/.ssh/${DOMAIN_SANITIZED}_deploy_ro -N "" -C "deploy-ro@$DOMAIN"

  # Set up SSH config with aliases
  cat >> /root/.ssh/config <<EOF

# GitHub deploy keys for $DOMAIN
Host github.com-${DOMAIN_SANITIZED}-rw
  HostName github.com
  User git
  IdentityFile /root/.ssh/${DOMAIN_SANITIZED}_deploy_rw
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new

Host github.com-${DOMAIN_SANITIZED}-ro
  HostName github.com
  User git
  IdentityFile /root/.ssh/${DOMAIN_SANITIZED}_deploy_ro
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
EOF

  # Extract repo path from URL (git@github.com:user/repo.git → user/repo)
  REPO_PATH=$(echo "$GITHUB_REPO_URL" | sed 's/.*:\(.*\)\.git/\1/')

  # Interactive prompt for user to add deploy keys
  echo ""
  echo "==================================================================="
  echo "  ADD DEPLOY KEYS TO GITHUB"
  echo "==================================================================="
  echo ""
  echo "Go to: https://github.com/$REPO_PATH/settings/keys"
  echo ""
  echo "1. Click 'Add deploy key'"
  echo "   Title: deploy-rw@$DOMAIN"
  echo "   Key:"
  echo ""
  cat /root/.ssh/${DOMAIN_SANITIZED}_deploy_rw.pub
  echo ""
  echo "   ☑ Check 'Allow write access'"
  echo ""
  echo "2. Click 'Add deploy key' again"
  echo "   Title: deploy-ro@$DOMAIN"
  echo "   Key:"
  echo ""
  cat /root/.ssh/${DOMAIN_SANITIZED}_deploy_ro.pub
  echo ""
  echo "   ☐ Leave 'Allow write access' UNCHECKED"
  echo ""
  echo "==================================================================="
  echo ""
  echo "Press ENTER when you've added both deploy keys to GitHub..."
  read

  # Push using RW key
  echo ""
  echo "=== Pushing to GitHub ==="
  git remote add origin "git@github.com-${DOMAIN_SANITIZED}-rw:${REPO_PATH}.git"

  if ! git push -u origin master 2>&1 | tee /tmp/git_push.log; then
    echo "  ERROR: Git push failed. Check /tmp/git_push.log for details"
    echo "  Common issues:"
    echo "  - Deploy key not added to GitHub"
    echo "  - Repository doesn't exist"
    echo "  - Wrong repository URL"
    exit 1
  fi

  # Switch remote to RO key
  echo "  Switching to read-only deploy key..."
  git remote set-url origin "git@github.com-${DOMAIN_SANITIZED}-ro:${REPO_PATH}.git"

  # Test RO key
  if ! git ls-remote origin &>/dev/null; then
    echo "  ERROR: Read-only deploy key not working"
    echo "  Check that you added the RO key to GitHub"
    exit 1
  fi
  echo "  ✓ Read-only deploy key working"

  # Push dev branch
  echo "  Pushing dev branch..."
  git checkout -b dev
  if ! git push -u origin dev 2>&1 | tee -a /tmp/git_push.log; then
    echo "  WARNING: Dev branch push failed"
  else
    echo "  ✓ Dev branch pushed"
  fi
  git checkout master

  # Delete RW key
  rm -f /root/.ssh/${DOMAIN_SANITIZED}_deploy_rw /root/.ssh/${DOMAIN_SANITIZED}_deploy_rw.pub
  echo "  ✓ Read-write key deleted from server"

  # Remove RW host from SSH config
  sed -i "/Host github.com-${DOMAIN_SANITIZED}-rw/,/^$/d" /root/.ssh/config
  echo "  ✓ Read-write SSH config removed"

  # Generate SSH key for GitHub Actions
  echo "  Generating SSH key for GitHub Actions..."
  ssh-keygen -t ed25519 -f /root/.ssh/github_actions_key -N "" -C "github-actions@$DOMAIN"

  # Add GHA public key to authorized_keys
  cat /root/.ssh/github_actions_key.pub >> /root/.ssh/authorized_keys
  echo "  ✓ GitHub Actions public key added to authorized_keys"

  # Print final instructions
  echo ""
  echo "==================================================================="
  echo "  GitHub Repository Setup Complete!"
  echo "==================================================================="
  echo ""
  echo "Repository: $GITHUB_REPO_URL"
  echo "Branch: master"
  echo ""
  echo "NEXT STEPS:"
  echo ""
  echo "1. Remove the READ-WRITE deploy key from GitHub:"
  echo "   https://github.com/$REPO_PATH/settings/keys"
  echo "   (Delete: deploy-rw@$DOMAIN)"
  echo "   (Keep: deploy-ro@$DOMAIN)"
  echo ""
  echo "2. Create GitHub environment 'deploy':"
  echo "   https://github.com/$REPO_PATH/settings/environments/new"
  echo "   - Environment name: deploy"
  echo "   - Deployment branches and tags: Selected branches and tags"
  echo "   - Add deployment branch rule 1: Branch name 'master'"
  echo "   - Add deployment branch rule 2: Branch name 'dev'"
  echo ""
  echo "3. Add these secrets to the 'deploy' environment:"
  echo "   https://github.com/$REPO_PATH/settings/environments"
  echo "   (Click on 'deploy' environment, then add secrets)"
  echo ""
  echo "   VPS_HOST: $DOMAIN"
  echo "   SSH_PORT: $SSH_PORT"
  echo "   VPS_SSH_KEY:"
  cat /root/.ssh/github_actions_key
  echo ""
  echo "==================================================================="
  echo ""
  echo "IMPORTANT: Add the secrets above to the 'deploy' environment now."
  echo "Do NOT store the VPS_SSH_KEY anywhere else - only in GitHub secrets."
  echo ""
  echo "Press ENTER after you've completed all steps above..."
  read

  # Delete GHA private key from server
  rm -f /root/.ssh/github_actions_key
  echo ""
  echo "  ✓ Setup complete!"
  echo "  Repository pushed with master and dev branches."
  echo "  Private key removed from server. Now stored only in GitHub Actions."
  echo "  This is secure and intended - GitHub Actions will use it to deploy."
  echo ""
fi

cd /root

# Restore default git advice
git config --global --unset advice.detachedHead

# Cleanup
rm -rf /tmp/webserver-printer
rm -f /root/init.sh /root/setup-config.sh /root/default.conf

# Restore interactive frontend
unset DEBIAN_FRONTEND

# Start Docker Compose stack
echo "=== Starting Docker containers ==="
cd "/root/$DOMAIN/docker"
docker compose up -d
echo "Containers started. Check status in lazydocker."
cd /root

echo "=== Setup complete ==="

# Send setup completion notification via Telegram
if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
  echo "  Sending Telegram notification..."

  MESSAGE="<b>✅ Server Setup Complete - $DOMAIN</b>

Your VPS has been successfully configured with webserver-printer.

<b>🔔 Notifications Enabled For:</b>
• <b>fail2ban</b> - IP bans from honeypot traps and SSH attacks
• <b>Container Health</b> - Alerts when Docker containers become unhealthy
• <b>Disk Space</b> - Warnings when disk usage exceeds 80%
• <b>Security Updates</b> - Weekly notifications about available updates

<b>📦 Services Running:</b>
• Frontend: https://$DOMAIN
• Logs: https://logs.$DOMAIN

<b>🔐 SSH Access:</b>
ssh -p $SSH_PORT root@$DOMAIN"

  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "parse_mode=HTML" \
    -d "text=${MESSAGE}" > /dev/null
fi

echo ""
echo "==================================================================="
echo "  Setup Complete!"
echo "==================================================================="
echo ""

# Reboot if requested
if [ "$REBOOT_AFTER" = true ]; then
  echo "Rebooting server in 5 seconds..."
  echo "Docker will auto-start on boot with all containers."
  sleep 5
  reboot
else
  echo "RECOMMENDATION: Reboot the server to apply all changes:"
  echo "  - SSH configuration changes (port, password auth)"
  echo "  - Kernel updates"
  echo "  - Verify Docker auto-starts on boot"
  echo ""
  echo "To reboot: sudo reboot"
  echo ""
  echo "After reboot, containers will auto-start (restart: unless-stopped)"
  echo "==================================================================="
  echo ""
fi
