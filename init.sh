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

# Install curl first (needed for downloading config)
echo "=== Installing curl ==="
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

apt install -y curl

# Determine editor preference and install (only if no config provided)
if [ -z "$USER_CONFIG_SOURCE" ]; then
  echo "=== Choose your preferred editor ==="
  echo "1) vim"
  echo "2) nano"
  read -p "Enter choice [1-2]: " editor_choice

  case $editor_choice in
  1) EDITOR="vim" ;;
  2) EDITOR="nano" ;;
  *)
    echo "Invalid choice"
    exit 1
    ;;
  esac

  echo "=== Installing $EDITOR ==="
  apt install -y $EDITOR
else
  # Default to vim if config is provided
  EDITOR="vim"
fi

# Load default configuration
CONFIG_FILE="/root/setup-config.sh"
echo "=== Loading default configuration ==="
curl -fsSL "$DEFAULT_CONFIG_URL" -o "$CONFIG_FILE"

# If user provided a config source, merge it
if [ -n "$USER_CONFIG_SOURCE" ]; then
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
else
  # No config provided, let user edit the default
  echo "=== Please fill in your configuration ==="
  $EDITOR "$CONFIG_FILE"
fi

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
  nano

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
echo "export EDITOR=$EDITOR" >>/root/.zshrc
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

# Create tmux config with plugins
cat >/root/.tmux.conf <<'EOF'
# List of plugins
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'tmux-plugins/tmux-yank'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'
set -g @plugin 'tmux-plugins/tmux-pain-control'
set -g @plugin 'tmux-plugins/tmux-copycat'

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
  {} \;

# Generate bcrypt password hash for Caddy basic_auth
ADMIN_PASSWORD_HASH=$(mkpasswd -m bcrypt -R 14 "$ADMIN_PASSWORD")

# Create .env file for docker-compose
cat >"/root/$DOMAIN/docker/.env" <<EOF
LOGS_USERNAME='$ADMIN_LOGIN'
LOGS_PASSWORD_HASH='$ADMIN_PASSWORD_HASH'
EOF

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

echo "=== Setup complete ==="
echo "=== Launching tmux session: $DOMAIN ==="
exec tmux new-session -s "$DOMAIN"
