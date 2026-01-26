# Multi-stage Dockerfile with language toolchain selector and minimal runtime
# Builds the Rust app in a dedicated builder stage, then copies the binary into a
# Debian stable-slim runtime with only the selected workspace toolchain installed.
# Supports LANG_TOOLCHAIN=rust|go|python to choose the workspace language tooling.

ARG LANG_TOOLCHAIN=rust

# Builder stage: compile Rust app (full toolchain here only)
FROM rust:1-slim AS builder-rust

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /app

# Copy only Cargo files first to cache dependency downloads
COPY Cargo.toml Cargo.lock* /app/

# Create dummy src to build deps (cached until Cargo.toml changes)
RUN mkdir -p src && echo "fn main() {}" > src/main.rs

ARG RELEASE=false
RUN if [ "$RELEASE" = "true" ]; then \
        cargo build --release; \
    else \
        cargo build; \
    fi && rm -rf src

# Now copy actual source (this layer rebuilds on code changes)
COPY src /app/src
COPY static /app/static

# Build actual binary (only recompiles vnccc, deps cached)
RUN if [ "$RELEASE" = "true" ]; then \
        touch src/main.rs && \
        cargo build --release && \
        cp target/release/vnccc target/vnccc; \
    else \
        touch src/main.rs && \
        cargo build && \
        cp target/debug/vnccc target/vnccc; \
    fi

# Toolchain stages: install only the selected workspace language tooling
# These stages are used by the runtime stage via LANG_TOOLCHAIN arg.
# They include only the runtime tooling needed for workspace development, not full
# build toolchains.

FROM debian:stable-slim AS toolchain-rust
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# Install minimal runtime dependencies for Rust workspace development
# - git: source control
# - curl: fetching tools
# - ca-certificates: TLS
# - gpg: key verification
# - libssl3: TLS runtime
# - pkg-config: build metadata (runtime only)
# - libgit2: git2 runtime
# - libssl-dev: needed for cargo crates that link OpenSSL
# - clang, lld, libclang-dev: for Rust crates that need libclang
# - cmake, make: for some build scripts
# - libfontconfig1, libegl1, libgl1, libgl1-mesa-dri: VNC/Alacritty rendering
# - bat, fd-find, ripgrep: dev utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    gpg \
    libssl3 \
    pkg-config \
    libssl-dev \
    clang \
    lld \
    libclang-dev \
    cmake \
    make \
    bat \
    fd-find \
    ripgrep \
    && rm -rf /var/lib/apt/lists/*

# Install rustup and default toolchain (runtime only, no build-essential)
ENV RUSTUP_HOME=/usr/local/rustup
ENV CARGO_HOME=/usr/local/cargo
ENV PATH="/usr/local/cargo/bin:${PATH}"
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile default

FROM debian:stable-slim AS toolchain-go
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# Install minimal runtime dependencies for Go workspace development
# - git, curl, ca-certificates, gpg: standard
# - libssl3: TLS runtime
# - golang-go: Go compiler and toolchain (runtime only)
# - make: for build scripts
# - libfontconfig1, libegl1, libgl1, libgl1-mesa-dri: VNC/Alacritty rendering
# - bat, fd-find, ripgrep: dev utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    libssl3 \
    gpg \
    golang-go \
    make \
    bat \
    fd-find \
    ripgrep \
    && rm -rf /var/lib/apt/lists/*

ENV GOPATH=/go
ENV PATH="/usr/local/go/bin:/go/bin:${PATH}"

FROM debian:stable-slim AS toolchain-python
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# Install minimal runtime dependencies for Python workspace development
# - git, curl, ca-certificates, gpg: standard
# - libssl3: TLS runtime
# - make: for build scripts
# - python3, python3-pip, python3-venv: Python runtime and venv support
# - bat, fd-find, ripgrep: dev utilities
# - astral-uv: universal venv manager
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    libssl3 \
    gpg \
    python3 \
    python3-pip \
    python3-venv \
    bat \
    make \
    fd-find \
    ripgrep \
    && rm -rf /var/lib/apt/lists/* \
    && curl -LsSf https://astral.sh/uv/install.sh | sh

FROM debian:stable-slim AS toolchain-node
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# Install minimal runtime dependencies for NodeJS + NextJS development
# - git, curl, ca-certificates, gpg: standard
# - libssl3: TLS runtime
# - make: for build scripts
# - nodejs, npm: NodeJS runtime and package manager
# - bun: fast JavaScript runtime
# - bat, fd-find, ripgrep: dev utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    libssl3 \
    gpg \
    make \
    bat \
    fd-find \
    ripgrep \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22.x (LTS) and Bun
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://bun.sh/install | bash \
    && ln -s /root/.bun/bin/bun /usr/local/bin/bun

ENV PATH="/usr/local/bin:${PATH}"

# Runtime stage: install VNC/UI and agent CLIs, copy built binary
# Uses the toolchain stage selected by LANG_TOOLCHAIN arg
FROM toolchain-${LANG_TOOLCHAIN} AS runtime
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# Install runtime VNC/UI dependencies
# - tigervnc-standalone-server, tigervnc-tools, novnc, websockify: VNC stack
# - xdotool: terminal automation
# - ratpoison: window manager
# - alacritty: terminal emulator
# - libfontconfig1, libegl1, libgl1, libgl1-mesa-dri: VNC/Alacritty rendering
# - openssh-client: for git over SSH
# - gh: GitHub CLI for checkout
# - build-essential: for native npm modules
# - procps: for process monitoring
# - curl, file: standard utilities
# - nodejs: for npm-based agent CLIs
# - fontconfig: font rendering
RUN apt-get update && apt-get install -y --no-install-recommends \
    tigervnc-standalone-server \
    tigervnc-tools \
    novnc \
    websockify \
    xdotool \
    ratpoison \
    alacritty \
    fontconfig \
    libfontconfig1 \
    libegl1 \
    libgl1 \
    libgl1-mesa-dri \
    libxcursor1 \
    libxi6 \
    libxrandr2 \
    libxrender1 \
    libxfixes3 \
    libxinerama1 \
    openssh-client \
    build-essential \
    procps \
    curl \
    file \
    gh \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22.x (LTS) for agent CLIs
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy built binary from builder
COPY --chmod=755 --from=builder-rust /app/target/vnccc /usr/local/bin/vnccc

# Copy assets and scripts
COPY static /app/static
COPY --chmod=755 scripts/provision-workspace.sh /app/
COPY --chmod=755 scripts/entrypoint.sh /app/
COPY --chmod=755 scripts/agent-wrapper.sh /usr/local/bin/agent
COPY --chmod=755 scripts/debug-agent-launcher.sh /usr/local/bin/debug-agent-launcher.sh
COPY alacritty.toml /app/

# Install agent CLI based on AGENT arg
ARG AGENT=claude
RUN if [ "$AGENT" = "claude" ]; then \
        npm install -g @anthropic-ai/claude-code; \
    elif [ "$AGENT" = "gemini" ]; then \
        npm install -g @google/gemini-cli; \
    elif [ "$AGENT" = "kilocode" ]; then \
        npm install -g @kilocode/cli; \
    elif [ "$AGENT" = "opencode" ]; then \
        npm install -g opencode-ai; \
    elif [ "$AGENT" = "crush" ]; then \
        npm install -g @charmland/crush; \
    elif [ "$AGENT" = "codex" ]; then \
        npm install -g @openai/codex; \
    else \
        echo "Unknown AGENT: $AGENT"; \
        exit 1; \
    fi

# Expose ports: 8080 (web UI), 6080 (noVNC websocket)
EXPOSE 8080 6080

# Force software rendering for headless VNC
ENV LIBGL_ALWAYS_SOFTWARE=1

# Default: run vnccc pointing to a mounted repo
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["/repo", "1920x1920", "8080"]
