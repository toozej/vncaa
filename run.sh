#!/bin/bash
set -e

BUILD_LOCAL=false
NOCACHE=""
RELEASE=false
REPO_PATH="."
DD=${DD:-it}
DEBUG=false
IMAGE="ghcr.io/toozej/vncaa:main"

# Parse args
while [ $# -gt 0 ]; do
    case $1 in
        --build)
            BUILD_LOCAL=true
            shift
            ;;
        --lang-toolchain)
            LANG_TOOLCHAIN="${2:-rust}"
            shift 2
            ;;
        --no-cache)
            NOCACHE="--no-cache"
            shift
            ;;
        --release)
            RELEASE=true
            shift
            ;;
        --agent)
            AGENT="$2"
            shift 2
            ;;
        --workspace)
            REPO_PATH="$2"
            shift 2
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        *)
            REPO_PATH="$1"
            shift
            ;;
    esac
done

AGENT=${AGENT:-claude}

# validate lang toolchain
case "$LANG_TOOLCHAIN" in
    go|rust|python|node)
        # Valid toolchain
        ;;
    *)
        echo "Error: Invalid LANG_TOOLCHAIN '$LANG_TOOLCHAIN'. Must be one of: go, rust, python, node"
        exit 1
        ;;
esac

# Set default remote image tag based on agent and lang toolchain
if [ "$BUILD_LOCAL" = false ]; then
    IMAGE="ghcr.io/toozej/vncaa:${AGENT}-${LANG_TOOLCHAIN}-main"
fi

# Resolve to absolute path
# Use git rev-parse if available and we're in a git repo, otherwise fall back to cd/pwd
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    REPO_PATH="$(git rev-parse --show-toplevel)"
else
    REPO_PATH="$(cd "$REPO_PATH" && pwd)"
fi

if [ "$BUILD_LOCAL" = true ]; then
    IMAGE="toozej/vncaa:${AGENT}-${LANG_TOOLCHAIN}-latest"
    echo "Building vncaa container locally (release=$RELEASE, agent=$AGENT, lang_toolchain=$LANG_TOOLCHAIN, no-cache=$NOCACHE)..."
    docker build --build-arg RELEASE=$RELEASE --build-arg AGENT="$AGENT" --build-arg LANG_TOOLCHAIN="$LANG_TOOLCHAIN" $NOCACHE -t "$IMAGE" "$REPO_PATH"
else
    echo "Pulling latest vncaa image from GHCR..."
    docker pull "$IMAGE"
fi

echo "Starting vncaa with repo: $REPO_PATH (agent: $AGENT)"
echo "Open http://localhost:8080 in your browser"

# Remove any existing container with same name
docker rm -f vncaa 2>/dev/null || true

MOUNT_OPTS=()
ENV_OPTS=()
MOUNT_OPTS+=(-v "$REPO_PATH:/repo:rw")
[ -f "$HOME/.gitconfig" ] && MOUNT_OPTS+=(-v "$HOME/.gitconfig:/tmp/host-gitconfig:ro")
[ -d "$HOME/.ssh" ] && MOUNT_OPTS+=(-v "$HOME/.ssh:/tmp/host-ssh:ro")
[ -d "$HOME/.config/gh" ] && MOUNT_OPTS+=(-v "$HOME/.config/gh:/tmp/host-gh-config:rw")

case "$AGENT" in
    claude)
        [ -f "$HOME/.claude.json" ] && MOUNT_OPTS+=(-v "$HOME/.claude.json:/tmp/host-claude.json:ro")
        [ -d "$HOME/.claude" ] && MOUNT_OPTS+=(-v "$HOME/.claude:/tmp/host-claude:rw")
        [ -d "$HOME/.config/claude" ] && MOUNT_OPTS+=(-v "$HOME/.config/claude:/tmp/host-claude-config:rw")
        ENV_OPTS+=(-e "CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN")
        ;;
    gemini)
        [ -d "$HOME/.gemini" ] && MOUNT_OPTS+=(-v "$HOME/.gemini:/tmp/host-gemini:rw")
        ;;
    kilocode)
        [ -d "$HOME/.kilocode" ] && MOUNT_OPTS+=(-v "$HOME/.kilocode:/tmp/host-kilocode:rw")
        ;;
    opencode)
        [ -d "$HOME/.config/opencode" ] && MOUNT_OPTS+=(-v "$HOME/.config/opencode:/tmp/host-opencode-config:rw")
        [ -d "$HOME/.opencode" ] && MOUNT_OPTS+=(-v "$HOME/.opencode:/tmp/host-opencode:rw")
        [ -n "$OPENCODE_CONFIG" ] && [ -f "$OPENCODE_CONFIG" ] && MOUNT_OPTS+=(-v "$OPENCODE_CONFIG:/tmp/host-opencode-file:ro")
        ENV_OPTS+=(-e "OPENCODE_CONFIG=$OPENCODE_CONFIG")
        [ -n "$OPENCODE_CONFIG_CONTENT" ] && ENV_OPTS+=(-e "OPENCODE_CONFIG_CONTENT=$OPENCODE_CONFIG_CONTENT")
        ;;
    crush)
        [ -d "$HOME/.config/crush" ] && MOUNT_OPTS+=(-v "$HOME/.config/crush:/tmp/host-crush-config:rw")
        ;;
    codex)
        [ -d "$HOME/.codex" ] && MOUNT_OPTS+=(-v "$HOME/.codex:/tmp/host-codex:rw")
        ;;
esac

echo "Mount options: ${MOUNT_OPTS[@]}"

docker run "-${DD}" --rm \
    -p 8080:8080 \
    -p 6080:6080 \
    -e HOST_UID="$(id -u)" \
    -e HOST_GID="$(id -g)" \
    -e HOST_USER="$(whoami)" \
    -e AGENT="$AGENT" \
    -e DEBUG="$DEBUG" \
    "${ENV_OPTS[@]}" \
    "${MOUNT_OPTS[@]}" \
    --name vncaa \
    "$IMAGE"
