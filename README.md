# vps-setup

Universal VPS Setup & Hardening Script for Ubuntu 20.04 / 22.04 / 24.04 LTS.

Configures a fresh server with security hardening, performance tuning, and Docker — without installing any specific application on top.

## Quick start

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/vps-setup/main/setup.sh)
```

Or with `wget`:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/YOUR_USERNAME/vps-setup/main/setup.sh)
```

> **Note:** Replace `YOUR_USERNAME` with your GitHub username.

---

## What it does

| Module | Description |
|--------|-------------|
| `system` | `apt upgrade` + essential packages (curl, git, htop, iftop, ...) |
| `docker` | Docker CE + Compose Plugin + sane `daemon.json` defaults |
| `sysctl` | TCP buffer tuning, IP forwarding, SYN-flood protection |
| `ulimits` | `nofile` / `nproc` = 1 048 576 / 65 536 (PAM + systemd) |
| `bbr` | TCP BBR congestion control + `fq` qdisc |
| `swap` | Auto-sized swap file based on available RAM |
| `ssh` | SSH hardening: disable root/empty passwords, tune timeouts |
| `firewall` | UFW: SSH + 80/443 + custom ports + optional trusted IP |
| `fail2ban` | Brute-force protection for SSH via UFW backend |
| `logrotate` | System and setup log rotation |
| `motd` | Informational login banner (IP, RAM, Disk, Uptime) |

Every module can be skipped independently with a `--skip-*` flag.

---

## Options

```
--skip-system       Skip system update and base packages
--skip-docker       Skip Docker installation
--skip-sysctl       Skip kernel parameter tuning
--skip-ulimits      Skip ulimit configuration
--skip-bbr          Skip TCP BBR
--skip-swap         Skip swap file creation
--skip-ssh          Skip SSH hardening
--skip-firewall     Skip UFW configuration
--skip-fail2ban     Skip Fail2Ban
--skip-logrotate    Skip logrotate configuration
--skip-motd         Skip MOTD banner

--new-ssh-port=N    Change SSH port to N (1024–65535)
--open-ports=LIST   Extra UFW ports: 8080,3000,9000/udp
--trusted-ip=IP     Allow full access from this IP (CIDR ok)
--non-interactive   No prompts — use defaults or provided flags
```

## Examples

```bash
# Interactive (recommended for first run)
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/vps-setup/main/setup.sh)

# Non-interactive with extra ports and a trusted management IP
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/vps-setup/main/setup.sh) \
  --non-interactive \
  --open-ports=8080,3000 \
  --trusted-ip=1.2.3.4

# Everything except Docker (already installed)
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/vps-setup/main/setup.sh) \
  --skip-docker

# Change SSH port to 2244, no BBR
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/vps-setup/main/setup.sh) \
  --new-ssh-port=2244 \
  --skip-bbr
```

---

## Requirements

- Ubuntu 20.04 / 22.04 / 24.04 LTS (Debian works with minor caveats)
- Root access (`sudo` or direct root)
- Internet connection

## Log

The full installation log is saved to `/var/log/vps-setup.log`.

## License

MIT
