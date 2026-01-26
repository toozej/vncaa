#!/bin/bash
# Debug wrapper for agent launcher - provides verbose logging

set -x  # Enable command tracing

echo "=== Agent Debug Launcher Start ==="
echo "Date: $(date)"
echo "User: $(whoami)"
echo "PWD: $(pwd)"
echo "HOME: $HOME"
echo "AGENT: $AGENT"
echo "PATH: $PATH"

REPO_DIR="$1"
echo "Target repo directory: $REPO_DIR"

if [ -z "$REPO_DIR" ]; then
    echo "ERROR: No repository directory provided" >&2
    exit 1
fi

if [ ! -d "$REPO_DIR" ]; then
    echo "ERROR: Repository directory does not exist: $REPO_DIR" >&2
    exit 1
fi

echo "Changing to: $REPO_DIR"
cd "$REPO_DIR" || {
    echo "ERROR: Failed to cd to $REPO_DIR" >&2
    exit 1
}
echo "New PWD: $(pwd)"

echo "Checking for agent wrapper..."
if ! command -v /usr/local/bin/agent >/dev/null 2>&1; then
    echo "ERROR: /usr/local/bin/agent not found" >&2
    echo "Available files in /usr/local/bin/:" >&2
    ls -la /usr/local/bin/ 2>&1 >&2
    exit 1
fi

echo "Agent wrapper found at: $(which /usr/local/bin/agent)"
echo "Agent wrapper permissions: $(ls -la /usr/local/bin/agent)"

echo "=== Executing agent ===="
/usr/local/bin/agent
EXIT_CODE=$?
echo "=== Agent exited with code: $EXIT_CODE ==="

exit $EXIT_CODE
