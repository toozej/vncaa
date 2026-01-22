# vnccc: vnc claude code

Run Claude Code in a VNC Linux environment for ease of use over tailscale/etc.

## Quick Start

```bash
# Get Claude Code OAuth token
claude setup-token
export CLAUDE_CODE_OAUTH_TOKEN=sk-...

# Run (pulls latest image from GitHub Container Registry)
./run.sh

# Or build locally for development
./run.sh --build
```

Open http://localhost:8080 in your browser.

The script automatically pulls the latest published image from GHCR. Use `--build` to build from source instead.

## Prerequisites

- Docker
- Claude Code CLI (`npm install -g @anthropic-ai/claude-code`)

## Configuration

The container automatically mounts your host configurations:

- **Git**: `.gitconfig` (for commits)
- **GitHub CLI**: `.config/gh/` (for `gh pr create`, `gh issue`, etc.)
- **SSH**: `.ssh/` (for git push over SSH)
- **Claude**: `.claude/` and `.config/claude/` (settings and session data)

To enable GitHub operations inside the container:

```bash
# Authenticate gh CLI on your host
gh auth login

# Your credentials will be available in the container
./run.sh
```

Inside the container, Claude Code can now create PRs, commit, and push.

## Building

```bash
git clone <repo-url>
cd vnccc
cargo build --release
```

## Features

- Mobile-friendly with swype keyboard support
- Square display aspect ratio for Android
- Per-repository configuration
- Dynamic font size adjustment from browser
- Automatic terminal restart on exit

## Architecture

- **Display**: TigerVNC + X11
- **Terminal**: Alacritty
- **Web client**: noVNC
- **Web server**: Axum (Rust)
- **Automation**: xdotool + Bash

## Remote Access

To access vnccc from other devices, use Tailscale on your host machine:

```bash
# Install and setup Tailscale on host
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up

# Run vnccc
./run.sh

# Access from any device on your tailnet
http://[tailscale-ip]:8080
```

The container uses host networking, so Tailscale running on the host provides secure remote access.

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details.
