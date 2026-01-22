FROM debian:trixie-slim

# Install system dependencies (rarely changes - cached)
RUN apt-get update && apt-get install -y \
    tigervnc-standalone-server \
    tigervnc-tools \
    novnc \
    websockify \
    xdotool \
    alacritty \
    curl \
    build-essential \
    git \
    ca-certificates \
    gpg \
    fontconfig \
    libfontconfig1 \
    libegl1 \
    libgl1 \
    libgl1-mesa-dri \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js and Claude Code (rarely changes - cached)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g @anthropic-ai/claude-code \
    && rm -rf /var/lib/apt/lists/*

# Setup Rust (rarely changes - cached)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

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
COPY alacritty.toml /app/

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

# Setup alacritty config
RUN mkdir -p /root/.config/alacritty && \
    cp /app/alacritty.toml /root/.config/alacritty/alacritty.toml

WORKDIR /root

# Expose ports: 8080 (web UI), 6080 (noVNC websocket)
EXPOSE 8080 6080

# Force software rendering for headless VNC
ENV LIBGL_ALWAYS_SOFTWARE=1

# Default: run vnccc pointing to a mounted repo
ENTRYPOINT ["/app/target/vnccc"]
CMD ["/repo", "1920x1920", "8080"]
