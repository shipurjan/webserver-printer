<img src="assets/logo.svg" alt="webserver-printer logo" width="200">

# webserver-printer

One command to provision a production-ready VPS with Docker, auto-HTTPS, fail2ban honeypots, GitHub CI/CD, and a Lighthouse-perfect SPA Astro frontend.

> **Note:** This is currently a personal script. It requires Debian 13 (Trixie), a domain pointed to your VPS, and SSH key access.

## What You Get

<img src="assets/lighthouse.png" alt="Deployed site with 100 Lighthouse scores">

The script creates a complete GitHub repo for your domain with a Dockerized web stack, CI/CD pipelines, and a starter Astro site optimized for 100 Lighthouse scores across Performance, Accessibility, Best Practices, and SEO.

## ⚠️ Security Warning

**This script runs as root and makes significant system changes.** Before running it:

1. **Read [init.sh](init.sh)** - Understand what it's doing to your system
2. **Verify the source** - You're downloading and executing code from GitHub
3. **Know the changes** - See "What Gets Installed" below

This is infrastructure automation, not magic. Read the code or don't run it.

## Usage

Run on any fresh Debian 13 (Trixie) VPS:

1. **Download the default config:**
   ```bash
   curl -fsSL https://raw.githubusercontent.com/shipurjan/webserver-printer/refs/heads/master/default.conf -o setup.conf
   ```

2. **Edit the config:**
   ```bash
   vim setup.conf  # Fill in your values
   ```

3. **Run the init script:**
   ```bash
   curl -fsSL https://raw.githubusercontent.com/shipurjan/webserver-printer/refs/heads/master/init.sh | bash -s -- setup.conf
   ```

The config file is merged with defaults, with your values overriding the base configuration.

## What Gets Installed

### Shell & Tools
- **Zsh** with Oh My Zsh + Powerlevel10k theme
- **Tmux** with TPM, session persistence, OSC 52 clipboard
- **Lazydocker** for Docker management
- CLI tools: ripgrep, fd-find, fzf, jq, vim, git, curl, wget

### Docker Stack
- **Frontend**: Astro + TypeScript + Tailwind CSS, pre-compressed (Brotli/zstd), View Transitions
- **Caddy**: Reverse proxy with auto-HTTPS, security headers, honeypot routes
- **Dozzle**: Log viewer at `logs.$DOMAIN`

### Security
- **SSH**: Key-only auth, optional custom port
- **fail2ban**: SSH protection + 50 honeypot patterns (wp-admin, phpmyadmin, .env, etc.), Docker-aware iptables
- **Caddy**: Bot blocking (GPTBot, CCBot, etc.), security headers, CSP
- **unattended-upgrades**: Automatic security-only updates from Debian Security
- **needrestart**: Automatic service restarts after library updates

## Monitoring (Optional)

The template includes optional monitoring scripts that send Telegram notifications:

### Available Scripts (`template/scripts/`)
- **health-check.sh** - Monitors container health, alerts on failures (every 5 min)
- **reboot-notify.sh** - Notifies when reboot is required after security updates (daily 7am)
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

Cron jobs are installed automatically. See [template/crontab.example](template/crontab.example) for schedule details.

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
- `SSH_PORT` - SSH port (default: 22, change to reduce bot spam)
- `AUTO_REBOOT` - Automatically reboot when kernel updates require it (default: false)
- `REBOOT_TIME` - Time for automatic reboot if enabled (default: 04:00)

## Template System

Files use `__#TEMPLATE#:VARIABLE__` placeholders that get replaced with your configuration:
- `__#TEMPLATE#:DOMAIN__` → Your domain
- `__#TEMPLATE#:EMAIL__` → Your email
- `__#TEMPLATE#:ADMIN_LOGIN__` → Admin username
- `__#TEMPLATE#:ADMIN_PASSWORD__` → Admin password

The placeholder format is designed to be compatible with Astro and other modern frontend frameworks.

## GitHub CI/CD

The template includes GitHub Actions workflows:

- **ci.yml** - Type checking and build validation on PR/push
- **deploy.yml** - SSH deployment to VPS after CI passes
- **lighthouse.yml** - Performance scoring on pull requests (runs 3x, averages results)
- **gitleaks.yml** - Daily secret scanning of git history

The init script generates Ed25519 deploy keys for GitHub and configures SSH aliases for seamless git operations.
