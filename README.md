# vps-webhost-init

A script to set up a fresh Debian/Ubuntu VPS for hosting dockerized websites.

## ⚠️ Security Warning

**This script runs as root and makes significant system changes.** Before running it:

1. **Read [init.sh](init.sh)** - Understand what it's doing to your system
2. **Verify the source** - You're downloading and executing code from GitHub
3. **Know the changes** - See "What Gets Installed" below

This is infrastructure automation, not magic. Read the code or don't run it.

## Usage

Run on any fresh Debian/Ubuntu VPS:

1. **Download the default config:**
   ```bash
   curl -fsSL https://raw.githubusercontent.com/shipurjan/vps-webhost-init/refs/heads/master/default.conf -o setup.conf
   ```

2. **Edit the config:**
   ```bash
   vim setup.conf  # Fill in your values
   ```

3. **Run the init script:**
   ```bash
   curl -fsSL https://raw.githubusercontent.com/shipurjan/vps-webhost-init/refs/heads/master/init.sh | bash -s -- setup.conf
   ```

The config file is merged with defaults, with your values overriding the base configuration.

### Automated Deployment to Hetzner Cloud

For automated deployment, use the included `deploy.sh` script:

1. **Setup credentials:**
   ```bash
   cp default.env .env
   vim .env  # Add your HETZNER_API_TOKEN and SSH_KEY
   ```

2. **Setup config:**
   ```bash
   cp default.conf deploy.conf
   vim deploy.conf  # Fill in DOMAIN, EMAIL, etc.
   ```

3. **Deploy:**
   ```bash
   ./deploy.sh
   ```

The script will automatically create a Hetzner server, update the config, and run the init script.

## What Gets Installed

### System Packages
- **Core tools**: curl, wget, git, tmux, ufw, fail2ban, jq, xsel
- **Developer tools**: vim, ripgrep, fd-find, whois, tree
- **Build essentials**: ca-certificates, gnupg, gawk, perl, grep, sed

### Developer Environment
- **Zsh** with Oh My Zsh framework
  - **Theme**: Powerlevel10k with pre-configured prompt
  - **Plugins**: git, docker, docker-compose, sudo, fzf, colored-man-pages, extract, history, command-not-found, ufw, zsh-autosuggestions
- **Tmux** with Plugin Manager (TPM)
  - **Plugins**: sensible, yank, resurrect, continuum, pain-control, copycat
  - **Features**: Vi key bindings, OSC 52 clipboard support over SSH
  - **Auto-attach**: Automatically enters tmux session on SSH login

### Docker Infrastructure
- **Docker & Docker Compose** - Latest stable versions
- **Lazydocker** - TUI for Docker management
- **Network**: Isolated Docker network for containers
- **Reverse Proxy**: Caddy with automatic HTTPS (Let's Encrypt)

### Security
- **fail2ban** - Intrusion prevention with custom honeypot detection
  - SSH brute force protection (3 failed attempts = 1 hour ban)
  - Honeypot traps for common attack paths (/wp-admin, /phpmyadmin, /.env, etc.)
  - Docker-aware iptables rules (uses DOCKER-USER chain)
  - Telegram alerts on bans (if configured)
- **UFW** - Firewall (available but not auto-configured)
- **Caddy honeypots** - Bot detection and blocking

### Project Structure
- Template copied to `/root/$DOMAIN/`
- Git repository initialized with initial commit
- Docker Compose stack with:
  - Frontend container (http-server on port 3000)
  - Caddy reverse proxy (ports 80/443)
  - Dozzle log viewer (logs.$DOMAIN)
- Environment files with bcrypt-hashed credentials

## Monitoring (Optional)

The template includes optional monitoring scripts that send Telegram notifications:

### Available Scripts (`template/scripts/`)
- **health-check.sh** - Monitors container health, alerts on failures (every 5 min)
- **security-updates-check.sh** - Weekly check for security updates (Sunday 9am)
- **disk-space-check.sh** - Alerts when disk usage exceeds 80% (daily 8am)
- **fail2ban** - Sends alerts when IPs are banned

### Setup Telegram Notifications

1. **Create a Telegram bot:**
   - Message [@BotFather](https://t.me/BotFather) on Telegram
   - Send `/newbot` and follow instructions
   - Copy the bot token (looks like `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`)

2. **Get your chat ID:**
   - Send `/start` to your new bot
   - Visit: `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
   - Find your chat ID in the response (looks like `123456789`)

3. **Add to your config:**
   ```bash
   TELEGRAM_BOT_TOKEN="123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
   TELEGRAM_CHAT_ID="123456789"
   ```

4. **Enable cron jobs:**
   ```bash
   (crontab -l 2>/dev/null; cat ~/[domain]/crontab.example) | crontab -
   ```

See [template/crontab.example](template/crontab.example) for cron schedule details.

**Note:** If you don't configure Telegram, monitoring scripts will silently skip notifications.

## Configuration

Default configuration in [default.conf](default.conf):
- `DOMAIN` - Your domain name
- `EMAIL` - Email for SSL certificates and git commits
- `FULL_NAME` - Name for git commits
- `ADMIN_LOGIN` - Username for monitoring dashboards
- `ADMIN_PASSWORD` - Password for monitoring dashboards
- `TELEGRAM_BOT_TOKEN` - (Optional) Bot token for monitoring alerts
- `TELEGRAM_CHAT_ID` - (Optional) Your Telegram chat ID for alerts

## Infrastructure Created

After running init.sh, you'll have:
- Zsh with Powerlevel10k as default shell
- Tmux session named after your domain with lazydocker in split pane
- Docker containers running your web stack
- SSL certificates automatically managed by Caddy
- fail2ban actively blocking attacks
- Git repository at `/root/$DOMAIN/` ready for version control

## Template System

Files use `{{%INIT_TEMPLATE%:VARIABLE}}` placeholders that get replaced with your configuration:
- `{{%INIT_TEMPLATE%:DOMAIN}}` → Your domain
- `{{%INIT_TEMPLATE%:EMAIL}}` → Your email
- `{{%INIT_TEMPLATE%:ADMIN_LOGIN}}` → Admin username
- `{{%INIT_TEMPLATE%:ADMIN_PASSWORD}}` → Admin password

## Local Development

To test or contribute to this project:

1. **Clone the repository:**
   ```bash
   git clone https://github.com/shipurjan/vps-webhost-init.git
   cd vps-webhost-init
   ```

2. **Setup Hetzner credentials:**
   ```bash
   cp default.env .env
   vim .env  # Add your HETZNER_API_TOKEN and SSH_KEY
   ```

3. **Setup deployment config:**
   ```bash
   cp default.conf deploy.conf
   vim deploy.conf  # Fill in your values
   ```

4. **Test deployment:**
   ```bash
   ./deploy.sh
   ```

The `.env` and `deploy.conf` files are gitignored to keep your credentials safe.
