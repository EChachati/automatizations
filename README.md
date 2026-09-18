# Automatizations

A collection of generic, public-ready automation scripts to set up a development environment on Arch-based systems (CachyOS, Arch, Manjaro, etc.).

Everything here is designed to be reusable and free of any company-specific references, so it can be safely shared or published.

## Requirements

- Arch-based Linux distribution
- An AUR helper (`paru` or `yay`) — used by several scripts (the base setup can also install `paru`)

## Shell support

The scripts run under Bash (via `#!/usr/bin/env bash`), so they work no matter your login shell. Environment variables and persistent lines are written shell-agnostically through `shell_config.sh`:

| Login shell | Config file written |
|-------------|---------------------|
| fish | `~/.config/fish/config.fish` (`set -gx NAME "value"`) |
| zsh | `~/.zshrc` (`export NAME="value"`) |
| bash | `~/.bashrc` (`export NAME="value"`) |

`install-setup-arch.sh` detects your login shell: on fish it keeps it (and can also install/switch to fish or zsh + Oh My Zsh if you prefer from the interactive prompt).

## Scripts

| Script | Description |
|--------|-------------|
| `install-setup-arch.sh` | Personal machine setup. Interactive menu to install base tools (zsh, git, Oh My Zsh), editors (Zed, Neovim, VSCodium, Cursor), Docker, gaming, apps, Python (pyenv + uv + Poetry), cloud tools, Claude Code and PostgreSQL (Docker Compose). |
| `install-git-ssh-connections.sh` | Interactive SSH key setup for GitHub (single, or personal + work) and GitLab accounts. Writes `~/.ssh/config` automatically and adds keys to the agent. |
| `install-vpn-pritunl.sh` | Installs the Pritunl VPN client and imports `.ovpn` profiles from `~/vpn/`. |
| `install-postgres.sh` | Full native PostgreSQL setup: install + init cluster, create a `development` database, Docker network access, restore from `.backup`, and optional DB manager (DBeaver / Beekeeper Studio). |
| `install-infra.sh` | Docker infrastructure setup: MinIO (object storage), Redis + Redis Commander, MongoDB and LocalStack (AWS emulator). All services share the `app-network` network. |
| `launcher.sh` | Menu-based launcher that lets you run any of the scripts above. |

## Docker configs

The `docker/` folder contains the configurations used by `install-infra.sh`:

| Folder | Services | Notes |
|--------|----------|-------|
| `docker/redis/` | Redis (port 6380) + Redis Commander UI (port 8081) | |
| `docker/mongodb/` | MongoDB (port 27017) | Resource-limited (500MB RAM, 1 CPU) |
| `docker/localstack/` | LocalStack (port 4566) | Requires `LOCALSTACK_AUTH_TOKEN` (prompted on first run) |

## Quick Start

```bash
git clone git@github.com:youruser/automatizations.git
cd automatizations
chmod +x *.sh
./launcher.sh
```

Or run any script directly:

```bash
./install-infra.sh
```

## Recommended setup order

For a fresh machine:

1. `install-setup-arch.sh` — base system and tools
2. `install-git-ssh-connections.sh` — SSH keys (do this before any work with remote repos)
3. `install-vpn-pritunl.sh` — VPN profiles (if needed)
4. `install-postgres.sh` — PostgreSQL
5. `install-infra.sh` — Docker infrastructure

## Environment variables

Set automatically by the scripts on first run and saved to `~/.zshrc`:

```bash
export LOCALSTACK_AUTH_TOKEN="your-token"
export GITHUB_TOKEN="your-token"
export GOOGLE_APPLICATION_CREDENTIALS="~/.config/gcloud/application_default_credentials.json"
```

## License

MIT