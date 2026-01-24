# vncaa - VNC Any [LLM] Agent [CLI]

A browser-based interface for running a LLM Agent CLI in a containerized environment.

## What It Does

vncaa creates a complete development environment accessible through your web browser. It combines:

- **VNC Server** (TigerVNC): Provides a virtual display
- **noVNC**: Browser-based VNC client for web access
- **Alacritty Terminal**: Modern GPU-accelerated terminal emulator
- **Ratpoison WM**: Lightweight tiling window manager
- **LLM Agent CLI**: Multi-agent support for various LLM Agent CLI tools including Claude Code, Gemini, Kilocode, OpenCode, Crush, and NanoCoder
- **Rust Web Server** (Axum): Serves the UI and handles interactions

## Architecture

### Core Components (src/main.rs:335-440)

The main application orchestrates several processes:

1. Finds an available X display (src/main.rs:42-50)
2. Starts Xvnc server with custom geometry (src/main.rs:52-80)
3. Launches websockify to bridge VNC and WebSocket (src/main.rs:82-93)
4. Starts ratpoison window manager (src/main.rs:95-103)
5. Opens Alacritty terminal running the selected LLM Agent CLI (src/main.rs:109-158)
6. Serves web UI with embedded noVNC viewer (src/index.html)

### Web Interface

The Axum server exposes three endpoints:

- `GET /` - Serves the HTML UI with embedded noVNC (src/main.rs:211-213)
- `GET /prompt` - WebSocket for sending text to the terminal (src/main.rs:215-233)
- `POST /api/font-size` - Dynamically adjust terminal font size (src/main.rs:235-271)

### Text Injection (src/main.rs:160-209)

Uses `xdotool` to:
1. Find the Alacritty window by class name
2. Focus the window
3. Type text and press Enter
4. Includes retry logic for terminal restarts

### Agent Wrapper (agent-wrapper.sh)

The `agent-wrapper.sh` script provides a unified interface for launching different LLM agents:

- **Claude**: `claude --dangerously-skip-permissions`
- **Gemini**: `gemini --yolo`
- **Kilocode**: `kilocode --yolo`
- **OpenCode**: `opencode --dangerously-skip-permissions`
- **Crush**: `crush --yolo`
- **NanoCoder**: `nanocoder`

The wrapper automatically detects the selected agent via the `AGENT` environment variable and executes the appropriate command with the correct flags.

### Auto-Restart (src/main.rs:380-401)

The terminal process runs in a monitor loop that automatically restarts it if it exits, ensuring the Claude Code session persists.

### Font Size Control (src/main.rs:291-332)

Dynamically updates the Alacritty TOML config file:
- Validates font size (8.0-72.0)
- Parses and updates the TOML configuration
- Alacritty live-reloads the config automatically

## Docker Setup

### Multi-Stage Build (Dockerfile)

The Dockerfile uses layer caching optimization:

1. **Base layer** (lines 4-26): System dependencies (VNC, terminal, tools, homebrew, Node.js)
2. **LLM Agent CLI tool** (lines 29-33): LLM CLI tool via homebrew or Node.js npm
3. **Dependency cache** (lines 38-47): Cargo dependencies with dummy source
4. **Application build** (lines 50-63): Actual vncaa binary compilation

Supports both debug and release builds via `RELEASE` build arg.

### Entrypoint (entrypoint.sh)

Creates a user matching host UID/GID to avoid permission issues:

- Creates user with matching UID/GID (entrypoint.sh:8-18)
- Mounts host configs via symlinks (entrypoint.sh:44-65)
- Copies git, SSH, Claude, and gh configs
- Sets up Alacritty configuration (entrypoint.sh:67-70)
- Runs vncaa as the created user (entrypoint.sh:88)

The entrypoint script handles agent-specific configuration mounting:

- **Claude**: Symlinks `.claude.json`, `.claude/`, and `.config/claude/`
- **Kilocode**: Symlinks `.kilocode/`
- **OpenCode**: Symlinks `.config/opencode/`, `.opencode/`, and custom config files
- **Crush**: Symlinks `.config/crush/`
- **NanoCoder**: Symlinks `.config/nanocoder/` and legacy preferences

## Running

### Quick Start (run.sh)

```bash
./run.sh /path/to/repo
```

The script:
1. Pulls the latest image from GitHub Container Registry (or builds locally with --build)
2. Mounts your repository and configs
3. Starts the container with proper port mappings (8080, 6080)
4. Preserves UID/GID for file permissions

### Mounted Configs

Automatically mounts if they exist:
- `.gitconfig` (read-only)
- `.ssh/` (read-only)
- `.config/gh/` (read-write)

Agent-specific configurations:

**Claude**:
- `.claude.json` (read-only)
- `.claude/` (read-write)
- `.config/claude/` (read-write)

**Kilocode**:
- `.kilocode/` (read-write)

**OpenCode**:
- `.config/opencode/` (read-write)
- `.opencode/` (read-write)
- Custom config file via `OPENCODE_CONFIG` environment variable

**Crush**:
- `.config/crush` (read-write)

**NanoCoder**:
- `.config/nanocoder/` (read-only)
- `.nanocoder-preferences.json` (read-only, legacy)

### Access

Open http://localhost:8080 in your browser to see the VNC session with Claude Code running.

## Features

### Browser Prompt Interface

The web UI includes a text input that sends commands directly to the terminal via WebSocket and xdotool automation (src/index.html).

### Dynamic Font Sizing

A slider control in the web UI adjusts the terminal font size in real-time by updating the Alacritty config file (src/main.rs:235-271).

### Mobile Optimized

The CSS includes responsive breakpoints and safe-area handling for mobile devices (src/index.html:209-245).

### Terminal Auto-Restart

If the terminal process exits (e.g., user quits Claude), it automatically restarts after 500ms (src/main.rs:383-401).

## CI/CD (.github/workflows/docker-build-push.yml)

GitHub Actions workflow on main branch:

1. **Test job**: Runs `cargo test`, `cargo fmt`, and `cargo clippy`
2. **Build job**: Builds release Docker image and pushes to GitHub Container Registry

Uses layer caching with GitHub Actions cache for faster builds.

## Dependencies (Cargo.toml)

- **axum**: Web framework with WebSocket support
- **tokio**: Async runtime
- **tower-http**: Middleware for serving files
- **serde/serde_json**: Serialization for font-size API
- **toml**: Parsing Alacritty config files

## Testing (src/main.rs:442-529)

Unit tests cover:
- Argument validation (geometry, port, repo path)
- Font size validation (range and validity)
- Display number allocation
- Terminal detection

Run with: `cargo test`

## Development

**IMPORTANT: Before committing ANY Rust code changes, you MUST run all three checks:**

```bash
# Run all checks before committing
cargo test
cargo fmt --check
cargo clippy --all-targets --all-features

# Fix formatting automatically
cargo fmt

# Fix clippy warnings (review suggestions first)
cargo clippy --fix --allow-dirty
```

These checks are enforced by CI and will fail the build if not passing. Always run them locally before pushing to save CI time and ensure code quality.

## Use Cases

1. **Remote Development**: Access Claude Code from any device with a browser
2. **Shared Environments**: Multiple users can run isolated Claude sessions
3. **Reproducible Setup**: Consistent development environment via Docker
4. **Mobile Access**: Work on code from tablets or phones
5. **Headless Servers**: Run Claude Code on servers without local GUI

## Technical Details

- Default resolution: 1920x1920 (configurable via CLI args)
- VNC port: 5900 + display number
- WebSocket port: 6080 (noVNC)
- Web UI port: 8080 (configurable)
- X11 software rendering: `LIBGL_ALWAYS_SOFTWARE=1`
- Rust edition: 2024

## Security Notes

- VNC runs with no authentication (`-SecurityTypes None`)
- Designed for local/trusted network use
- Bind address: `0.0.0.0` (all interfaces)
- Claude runs with `--dangerously-skip-permissions` flag

## Project Structure

```
.
├── src/
│   ├── main.rs           # Rust application (VNC orchestration + web server)
│   └── index.html        # Web UI with noVNC and prompt interface
├── Dockerfile            # Multi-stage build with layer caching
├── entrypoint.sh         # User creation and config mounting
├── run.sh                # Pull and run helper script (--build for local builds)
├── alacritty.toml        # Terminal configuration
├── Cargo.toml            # Rust dependencies
└── .github/workflows/    # CI for tests and Docker build
```
