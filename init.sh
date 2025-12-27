#!/bin/bash
set -e

# Prevent interactive prompts during package installation
export DEBIAN_FRONTEND=noninteractive

# Pinned versions
OHMYZSH_COMMIT="92aed2e93624124182ba977a91efa5bbe1e76d5f"
ZSH_AUTOSUGGESTIONS_COMMIT="85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5"
POWERLEVEL10K_COMMIT="36f3045d69d1ba402db09d09eb12b42eebe0fa3b"
LAZYDOCKER_COMMIT="78edbf3d2e3bb79440bdb88f4382cab9f81c43e4"
TPM_COMMIT="99469c4a9b1ccf77fade25842dc7bafbc8ce9946"

# Default config URL
DEFAULT_CONFIG_URL="https://raw.githubusercontent.com/shipurjan/vps-webhost-init/refs/heads/master/default.conf"

# Parse command line argument
USER_CONFIG_SOURCE="$1"

# Require config file
if [ -z "$USER_CONFIG_SOURCE" ]; then
  echo "Error: Config file path is required"
  echo "Usage: $0 <config-file>"
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
echo "=== Loading default configuration ==="
curl -fsSL "$DEFAULT_CONFIG_URL" -o "$CONFIG_FILE"

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
EOF

rm -f "$USER_CONFIG_FILE"

# Source the final configuration
source "$CONFIG_FILE"

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

echo "=== Installing Docker ==="
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" >/etc/apt/sources.list.d/docker.list

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

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
curl -fsSL https://raw.githubusercontent.com/shipurjan/vps-webhost-init/refs/heads/master/p10k.zsh -o /root/.p10k.zsh
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

# Auto-attach to tmux session on SSH login
if [[ -z "$TMUX" ]] && [[ -n "$SSH_CONNECTION" ]]; then
  TMUX_SESSION=$(tmux ls 2>/dev/null | head -n1 | cut -d: -f1)
  if [[ -n "$TMUX_SESSION" ]]; then
    exec tmux attach-session -t "$TMUX_SESSION"
  fi
fi
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
set -s escape-time 15

# Initialize TMUX plugin manager (keep this line at the very bottom of tmux.conf)
run '~/.tmux/plugins/tpm/tpm'
EOF

# Install tmux plugins
/root/.tmux/plugins/tpm/bin/install_plugins

# Clone repo and scaffold project from template
git clone --depth=1 https://github.com/shipurjan/vps-webhost-init.git /tmp/vps-webhost-init
cp -r /tmp/vps-webhost-init/template "/root/$DOMAIN"

# Replace placeholders with config values
find "/root/$DOMAIN" -type f -exec sed -i \
  -e "s|{{%INIT_TEMPLATE%:DOMAIN}}|$DOMAIN|g" \
  -e "s|{{%INIT_TEMPLATE%:EMAIL}}|$EMAIL|g" \
  -e "s|{{%INIT_TEMPLATE%:ADMIN_LOGIN}}|$ADMIN_LOGIN|g" \
  -e "s|{{%INIT_TEMPLATE%:ADMIN_PASSWORD}}|$ADMIN_PASSWORD|g" \
  -e "s|{{%INIT_TEMPLATE%:TELEGRAM_BOT_TOKEN}}|${TELEGRAM_BOT_TOKEN:-}|g" \
  -e "s|{{%INIT_TEMPLATE%:TELEGRAM_CHAT_ID}}|${TELEGRAM_CHAT_ID:-}|g" \
  {} \;

# Make scripts executable
chmod +x "/root/$DOMAIN/scripts/"*.sh

# Generate bcrypt password hash for Caddy basic_auth
ADMIN_PASSWORD_HASH=$(mkpasswd -m bcrypt -R 14 "$ADMIN_PASSWORD")

# Create .env file for docker-compose
cat >"/root/$DOMAIN/docker/.env" <<EOF
LOGS_USERNAME='$ADMIN_LOGIN'
LOGS_PASSWORD_HASH='$ADMIN_PASSWORD_HASH'
EOF

echo "=== Configuring fail2ban for honeypot protection ==="

# Create Caddy log directory
mkdir -p /var/log/caddy

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
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
action = iptables[name=SSH, port=ssh, protocol=tcp]
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
git -c user.email='<>' -c user.name='vps-webhost-init' commit -m "init"

# Set git identity for future commits
git config --global user.email "$EMAIL"
git config --global user.name "$FULL_NAME"
cd /root

# Restore default git advice
git config --global --unset advice.detachedHead

# Cleanup
rm -rf /tmp/vps-webhost-init
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

# Sanitize domain name for tmux session (only alphanumeric and underscore allowed)
TMUX_SESSION=$(echo "$DOMAIN" | sed 's/[^a-zA-Z0-9_]/_/g')
echo "=== Creating tmux session: $TMUX_SESSION ==="

# Create detached session in project directory (skip if exists)
if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  tmux new-session -d -s "$TMUX_SESSION" -c "/root/$DOMAIN"

  # Split window vertically (left 70%, right 30%)
  tmux split-window -h -t "$TMUX_SESSION:0" -p 30

  # Select left pane (pane 0) - main console
  tmux select-pane -t "$TMUX_SESSION:0.0"

  # Send lazydocker command to right pane (pane 1)
  tmux send-keys -t "$TMUX_SESSION:0.1" 'lazydocker' C-m

  echo "Tmux session created."
fi

# Attach if running interactively
if [ -e /dev/tty ]; then
  echo "Attaching to tmux session..."
  exec </dev/tty
  exec tmux attach-session -t "$TMUX_SESSION"
else
  echo "Non-interactive mode. Connect via SSH to auto-attach."
fi
