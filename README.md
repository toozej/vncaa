# vnccc: vnc claude code

vnccc is a program for running Claude Code in a VNC Linux environment with nice web and Android clients.

## Architecture

- Claude Code
- Rust
- Bash
- noVNC or similar/better
- Tailscale or routing layer (maybe Wireguard)
- Chrome, Firefox
- Arch Linux
- Install
  - Per-git-repo configuration/setup
  - Authenticate via SSH or OAuth flow for diff repo access

## Behavior

- Swype-keyboard friendly prompt box for easy mobile usage
- VNC can be taken control of but goal is to fully drive via Claude Code
- Auto resizing VNC with square default output on Android

---

## Getting Started

### Prerequisites

- **Rust**: Install via [rustup](https://rustup.rs/)
- **Linux environment**: Arch Linux recommended (or use a container)
- **VNC client**: noVNC (web), bVNC (Android), or any VNC viewer
- **Claude Code**: Installed and authenticated in the target environment

### Building the Project

```bash
git clone <repo-url>
cd vnccc
cargo build --release
```

### Running vnccc

```bash
cargo run
# or after building:
./target/release/vnccc
```

### Connecting via Web Client (noVNC)

1. Start the vnccc session
2. Launch noVNC websocket proxy pointing to VNC display
3. Open `http://<host>:6080/vnc.html` in browser
4. Connect with configured credentials

### Connecting via Android

1. Install bVNC or similar from F-Droid/Play Store
2. Configure connection to Tailscale/Wireguard IP
3. Set display to square aspect ratio for optimal mobile viewing
4. Use swype keyboard for prompt input

---

## Configuration

### Per-Repo Setup Workflow

Each git repository can have its own vnccc configuration:

1. Initialize config in repo root or `~/.config/vnccc/`
2. Specify Claude Code project settings
3. Configure display preferences
4. Set authentication method

### Authentication Options

- **SSH keys**: Standard key-based auth for repo access
- **OAuth flow**: GitHub/GitLab OAuth for web-based setup
- **API keys**: Claude API authentication via environment or config file

### VNC Display Settings

| Setting | Description | Default |
|---------|-------------|---------|
| Resolution | Display dimensions | 1024x768 |
| Square mode | Mobile-optimized aspect | Off |
| Color depth | Bits per pixel | 24 |
| Compression | VNC encoding | Tight |

### Network/Routing Configuration

**Tailscale (recommended for simplicity)**:
- Enable in Tailscale admin console
- Device appears in MagicDNS automatically
- No port forwarding required

**Wireguard (self-hosted option)**:
- Generate keypairs for server and clients
- Configure allowed IPs and endpoints
- More control over routing

---

## Implementation Notes / Design

### VNC/X11 Setup

#### VNC Server Options

| Server | Pros | Cons |
|--------|------|------|
| **TigerVNC** | Well-maintained, good performance | Larger footprint |
| **x11vnc** | Shares existing X display | Requires running X |
| **TurboVNC** | Optimized for high-bandwidth | More complex setup |

For vnccc, TigerVNC is the likely choice for headless server scenarios.

#### Window Manager Choices

Lightweight options for minimal overhead:
- **i3**: Tiling WM, keyboard-driven, minimal resources
- **dwm**: Even lighter, requires compilation for config
- **No WM**: Run terminal directly on root window (simplest)

#### Display Sizing Strategies

- **Fixed resolution**: Set at VNC server start (e.g., `Xvnc :1 -geometry 1024x1024`)
- **Dynamic resize**: Use `xrandr` to change resolution on client request
- **Auto-square**: Detect mobile client and switch to 1:1 aspect ratio

#### X11 vs Wayland

X11 is the pragmatic choice for now:
- Better VNC server support
- More mature tooling
- Claude Code terminal emulators work well
- Wayland compositors add complexity without clear benefit here

### Claude Code Integration

#### Terminal Emulator Selection

| Terminal | Consideration |
|----------|--------------|
| **Alacritty** | GPU-accelerated, Rust-based, fast |
| **Kitty** | Feature-rich, good font rendering |
| **xterm** | Universal fallback, minimal deps |
| **foot** | Wayland-native (if Wayland path) |

Alacritty is a natural fit given vnccc is Rust-based.

#### How Claude Code Runs Inside the Session

1. VNC server starts X display
2. Terminal emulator launches fullscreen/maximized
3. Claude Code starts in terminal (interactive mode)
4. User interacts via VNC input or vnccc automation layer

#### Input/Output Handling for Mobile

- Large font sizes for readability
- Touch-friendly scrollback
- Swype keyboard integration via Android IME
- Consider dedicated prompt input field overlay

#### Session Persistence and Recovery

- Use `tmux` or `screen` for session persistence
- Auto-attach on reconnect
- Save/restore conversation state on disconnect
- Handle network interruptions gracefully

### Networking Layer

#### Tailscale

- **Pros**: Zero-config, built-in auth, MagicDNS, NAT traversal
- **Cons**: Requires Tailscale account, third-party dependency
- **Setup**: `tailscale up` on server, connect from any Tailscale device

#### Wireguard

- **Pros**: Self-hosted, minimal, kernel-level performance
- **Cons**: Manual key management, NAT config needed
- **Setup**: Generate keys, configure peers, open UDP port

#### noVNC Websocket Proxy

```bash
# Example: websockify bridging VNC to websocket
websockify --web=/usr/share/novnc 6080 localhost:5901
```

Allows browser-based VNC without native client.

#### Security Considerations

- **Encryption**: VNC over TLS, or tunnel through Tailscale/Wireguard
- **Authentication**: VNC password + network-level auth (Tailscale identity)
- **Firewall**: Only expose VNC on private network interfaces
- **No public exposure**: Always use VPN/tunnel layer

### Open Questions

- [ ] Containerized vs bare metal deployment?
  - Container: Reproducible, isolated, easier multi-instance
  - Bare metal: Simpler, direct hardware access
- [ ] Multi-user support needs?
  - Separate VNC sessions per user?
  - Shared session with access control?
- [ ] Potential Rust crates to use:
  - VNC protocol: `vnc-rs`, custom impl?
  - X11 interaction: `x11rb`, `xcb`
  - Config: `serde`, `toml`
  - Networking: `tokio`, `reqwest`

---

## Roadmap / TODO

### Implemented

- [x] Project scaffold (Cargo.toml, main.rs)
- [x] Basic documentation

### In Progress

- [ ] Core architecture design

### Planned

- [ ] VNC server setup/management
- [ ] X11 display initialization
- [ ] Terminal emulator integration
- [ ] Claude Code session management
- [ ] noVNC proxy integration
- [ ] Tailscale/Wireguard configuration helpers
- [ ] Per-repo config system
- [ ] Mobile-optimized display modes
- [ ] Session persistence (tmux integration)
- [ ] Authentication flow (SSH/OAuth)

---

## Contributing

This project is in early development. Check the open questions and roadmap for areas that need exploration.

## License

TBD
