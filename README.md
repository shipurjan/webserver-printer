# vps-webhost-init

A script to set up a fresh Debian/Ubuntu VPS for hosting dockerized websites.

## Usage

Run on a fresh Debian/Ubuntu server:

```bash
curl -fsSL https://raw.githubusercontent.com/shipurjan/vps-webhost-init/refs/heads/master/init.sh | bash
```

## Local testing

```bash
docker build -t setup-hetzner . && docker run --rm -it setup-hetzner
```
