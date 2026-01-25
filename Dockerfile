FROM rust:1-slim-trixie

# Install system dependencies (rarely changes - cached)
RUN apt-get update && apt-get install -y \
    tigervnc-standalone-server \
    tigervnc-tools \
    novnc \
    websockify \
    xdotool \
    ratpoison \
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
    bat \
    fd-find \
    ripgrep \
    gh \
    && rm -rf /var/lib/apt/lists/*

ENV PATH="/root/.cargo/bin:${PATH}"
# Install Node.js (rarely changes - cached)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Create linuxbrew user for Homebrew installation
RUN useradd -m -s /bin/bash linuxbrew && \
    chown -R linuxbrew:linuxbrew /home/linuxbrew && \
    chmod 755 /home/linuxbrew

# Install Linuxbrew as linuxbrew user
RUN su - linuxbrew -c 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
ENV HOMEBREW_PREFIX=/home/linuxbrew/.linuxbrew
ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"

WORKDIR /app

# Copy only Cargo files first to cache dependency downloads
COPY Cargo.toml Cargo.lock* /app/

# Create dummy src to build deps (cached until Cargo.toml changes)
RUN mkdir -p src && echo "fn main() {}" > src/main.rs
ARG RELEASE=false
ARG AGENT=claude
RUN if [ "$AGENT" = "claude" ]; then \
        npm install -g @anthropic-ai/claude-code; \
    elif [ "$AGENT" = "gemini" ]; then \
        su - linuxbrew -c 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && brew install gemini-cli'; \
    elif [ "$AGENT" = "kilocode" ]; then \
        npm install -g @kilocode/cli; \
    elif [ "$AGENT" = "opencode" ]; then \
        su - linuxbrew -c 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && brew install anomalyco/tap/opencode'; \
    elif [ "$AGENT" = "crush" ]; then \
        su - linuxbrew -c 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && brew install charmbracelet/tap/crush'; \
    elif [ "$AGENT" = "nanocoder" ]; then \
        su - linuxbrew -c 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && brew tap nano-collective/nanocoder https://github.com/Nano-Collective/nanocoder && brew install nanocoder'; \
    else \
        echo "Unknown AGENT: $AGENT"; \
        exit 1; \
    fi
RUN if [ "$RELEASE" = "true" ]; then \
        cargo build --release; \
    else \
        cargo build; \
    fi && rm -rf src

# Now copy actual source (this layer rebuilds on code changes)
COPY src /app/src
COPY static /app/static
COPY alacritty.toml /app/
COPY entrypoint.sh /app/
COPY agent-wrapper.sh /usr/local/bin/agent
RUN chmod +x /usr/local/bin/agent

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

RUN chmod +x /app/entrypoint.sh

# Expose ports: 8080 (web UI), 6080 (noVNC websocket)
EXPOSE 8080 6080

# Force software rendering for headless VNC
ENV LIBGL_ALWAYS_SOFTWARE=1

# Default: run vnccc pointing to a mounted repo
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["/repo", "1920x1920", "8080"]
