#!/bin/bash
set -e

RELEASE=false
REPO_PATH="."

# Parse args
for arg in "$@"; do
    case $arg in
        --release)
            RELEASE=true
            ;;
        *)
            REPO_PATH="$arg"
            ;;
    esac
done

# Resolve to absolute path
REPO_PATH="$(cd "$REPO_PATH" && pwd)"

echo "Building vnccc container (release=$RELEASE)..."
docker build --build-arg RELEASE=$RELEASE -t vnccc .

echo "Starting vnccc with repo: $REPO_PATH"
echo "Open http://localhost:8080 in your browser"

# Remove any existing container with same name
docker rm -f vnccc 2>/dev/null || true

docker run -it --rm \
    -p 8080:8080 \
    -p 6080:6080 \
    -v "$HOME/.gitconfig:/root/.gitconfig:ro" \
    -v "$HOME/.ssh:/root/.ssh:ro" \
    -v "$REPO_PATH:/repo:rw" \
    -v "$HOME/.claude:/root/.claude:rw" \
    -v "$HOME/.config/claude:/root/.config/claude:rw" \
    --name vnccc \
    vnccc
