# vncaa: vnc LLM agent CLI

Run various LLM agent CLIs (Claude Code, KiloCode, OpenCode, Crush) in a VNC Linux environment for ease of use over tailscale/etc.

Credit where credit is due, most of the hard work for this application was done by "pgray" in [vnccc](https://github.com/pgray/vnccc). This fork adds the ability to run other LLM agent CLI tools as well as Claude Code using the same framework.

Here's an example of [vnccc](https://github.com/pgray/vnccc) running Claude Code:

https://github.com/user-attachments/assets/c95b450e-30d4-4c17-bc84-ed936f600d63

([vncaa](https://github.com/toozej/vncaa) would look identical if you selected "--agent claude", or a bit different if you selected a different LLM agent CLI like kilocode)


## Quick Start

```bash
# Setup OAuth token for your chosen agent (example for Claude)
claude setup-token
export CLAUDE_CODE_OAUTH_TOKEN=sk-...

# Run with default agent (Claude) and default language toolchain (Rust) - pulls latest image from GitHub Container Registry
./run.sh

# Or build locally for development
./run.sh --build

# Or specify a different agent and language toolchain at runtime
AGENT=kilocode LANG_TOOLCHAIN=python ./run.sh
# or
./run.sh --agent kilocode --lang-toolchain python

# Or build with a specific agent and language toolchain
./run.sh --build --agent opencode --lang-toolchain go

# Override workspace path (default: current directory or git root)
./run.sh --workspace /path/to/your/repo
```

Open http://localhost:8080 in your browser.

## Prerequisites

- Docker
- One of the supported LLM agent CLIs installed on host (for setup/auth):
  - Claude Code: `npm install -g @anthropic-ai/claude-code`
  - Gemini: `npm install -g @google/gemini-cli`
  - KiloCode: `npm install -g @kilocode/cli`
  - OpenCode: `npm install -g opencode-ai`
  - Crush: `npm install -g @charmland/crush`
  - Codex: `npm install -g @openai/codex`

## Configuration

The container automatically mounts your host configurations:

- **Git**: `.gitconfig` (for commits)
- **GitHub CLI**: `.config/gh/` (for `gh pr create`, `gh issue`, etc.)
- **SSH**: `.ssh/` (for git push over SSH)

### Agent-Specific Configurations

- **Claude**: `.claude/` and `.config/claude/` (settings and session data)
- **Gemini**: `.gemini/` (directory)
- **KiloCode**: `.kilocode/` (directory)
- **OpenCode**:
  - `.config/opencode/` (directory)
  - `.opencode/` (directory, if present)
  - Custom config file if `OPENCODE_CONFIG` env var points to an existing file
- **Crush**: `.config/crush/` (directory)
- **Codex**: `.codex/` (directory for user config)

To enable GitHub operations inside the container:

```bash
# Authenticate gh CLI on your host
gh auth login

# Your credentials will be available in the container
./run.sh
```

Inside the container, the selected agent can now create PRs, commit, and push.

## Building

```bash
git clone <repo-url>
cd vncaa
# Build with default agent (Claude) and Rust toolchain
docker build --build-arg AGENT=claude --build-arg LANG_TOOLCHAIN=rust -t vncaa .
# Or specify a different agent and toolchain
docker build --build-arg AGENT=kilocode --build-arg LANG_TOOLCHAIN=python -t vncaa-kilocode .
# Supported toolchains: rust (default), go, python, node
cargo build --release
```

## Features

- Support for several popular LLM Agent CLI tools
- Easily expandable to other LLM Agent CLI tools installable via homebrew or npm
- Support for variety of common language toolchains in runtime image (rust, python, go, node)
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

To access vncaa from other devices, use Tailscale on your host machine:

```bash
# Install and setup Tailscale on host
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up

# Run vncaa
./run.sh

# Access from any device on your tailnet
http://[tailscale-ip]:8080
```

The container uses host networking, so Tailscale running on the host provides secure remote access.

## Docker Compose

To run vncaa with docker-compose, use the provided `docker-compose.yml`:

```bash
# Mount a local workspace (default mode)
docker-compose up -d

# Or checkout a repository into a temporary workspace
docker-compose up -d
# with environment variables:
# WORKSPACE_MODE=checkout
# WORKSPACE_REPO=owner/repo
# WORKSPACE_REF=main
# GH_TOKEN=your_github_token (optional for private repos)
```

Example `.env` file for checkout mode:

```ini
WORKSPACE_MODE=checkout
WORKSPACE_REPO=toozej/vncaa
WORKSPACE_REF=main
GH_TOKEN=
```

Then run:

```bash
docker-compose up -d
```

## Systemd (user service)

To run vncaa automatically on startup as a user service:

1. Copy the unit file to your user systemd directory:

```bash
mkdir -p ~/.config/systemd/user
cp systemd/user/vncaa.service ~/.config/systemd/user/vncaa.service
```

2. Edit the unit file to set the correct `WorkingDirectory` and `ExecStart` paths:

```bash
# Open the unit file
vim ~/.config/systemd/user/vncaa.service

# Update these lines to point to your vncaa repo:
WorkingDirectory=/path/to/your/vncaa/repo
ExecStart=/path/to/your/vncaa/repo/run.sh
```

3. Create an environment file for configuration (optional):

```bash
mkdir -p ~/.config/vncaa
vim ~/.config/vncaa/env
```

Add your configuration variables:

```ini
# Agent selection (default: claude)
AGENT=kilocode

# OAuth token for Claude
CLAUDE_CODE_OAUTH_TOKEN=sk-...

# Other agent-specific tokens as needed
```

4. Enable linger for your user (so services run even when not logged in):

```bash
loginctl enable-linger $USER
```

5. Reload systemd and enable the service:

```bash
systemctl --user daemon-reload
systemctl --user enable vncaa.service
systemctl --user start vncaa.service
```

### Service Management

- **Start**: `systemctl --user start vncaa.service`
- **Stop**: `systemctl --user stop vncaa.service`
- **Restart**: `systemctl --user restart vncaa.service`
- **Status**: `systemctl --user status vncaa.service`
- **Logs**: `journalctl --user -u vncaa.service -f`
- **Reload unit files**: `systemctl --user daemon-reload`

The service will automatically start after networking is available and Docker is ready.

## Favicon

The [Vecna](https://strangerthings.fandom.com/wiki/Vecna)-esque PNG was generated using ChatGPT and converted to the various favicon formats using [favicon.io](https://favicon.io/). It was chosen as a joke since vncaa kind of sounds like Vecna.

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details.
