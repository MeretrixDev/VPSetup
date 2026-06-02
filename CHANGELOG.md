# Changelog

All notable changes to this project will be documented here.

## [1.0.1] — 2025-06-02

### Fixed
- SSH module: `PermitRootLogin` no longer silently set to `prohibit-password`.
  Now asks the user explicitly — defaults to `yes` (password login kept).
  Prevents lockout for users without SSH keys configured.

## [1.0.0] — 2025-06-02

### Added
- Initial release
- Modules: system, docker, sysctl, ulimits, bbr, swap, ssh, firewall, fail2ban, logrotate, motd
- All modules individually skippable via `--skip-*` flags
- Non-interactive mode (`--non-interactive`)
- Custom SSH port (`--new-ssh-port`)
- Custom UFW ports (`--open-ports`)
- Trusted IP (`--trusted-ip`)
