# vps-webhost-init

A script to set up a fresh Debian/Ubuntu VPS for hosting dockerized websites.

## Usage

Run on a fresh Debian/Ubuntu server:

```bash
curl -fsSL https://raw.githubusercontent.com/shipurjan/vps-webhost-init/refs/heads/master/init.sh | bash < /dev/tty
```

### Using a custom configuration file

You can provide a configuration file (local or remote) to skip interactive prompts:

```bash
# With a local config file
curl -fsSL https://raw.githubusercontent.com/shipurjan/vps-webhost-init/refs/heads/master/init.sh | bash -s -- /path/to/config.conf < /dev/tty

# With a remote config file
curl -fsSL https://raw.githubusercontent.com/shipurjan/vps-webhost-init/refs/heads/master/init.sh | bash -s -- https://example.com/config.conf < /dev/tty
```

The custom config file will be merged with [default.conf](default.conf), with your values overriding the defaults.

## Local testing

```bash
docker build -t setup-hetzner . && docker run --rm -it setup-hetzner
```
