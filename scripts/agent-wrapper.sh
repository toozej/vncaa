#!/bin/bash

AGENT=${AGENT:-claude}

# Helper to execute agent and handle failures
exec_agent() {
    local cmd="$1"
    shift
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: '$cmd' not found in PATH"
        echo "PATH: $PATH"
        exit 1
    fi
    exec "$cmd" "$@" || {
        echo "Failed to execute '$cmd' (exit code: $?)"
        echo "Sleeping for 30s to allow inspection..."
        sleep 30
        exit 1
    }
}

case "$AGENT" in
    claude)
        exec_agent claude --dangerously-skip-permissions "$@"
        ;;
    gemini)
        exec_agent gemini --yolo "$@"
        ;;
    kilocode)
        exec_agent kilocode --yolo "$@"
        ;;
    opencode)
        # TODO '--dangerously-skip-permissions' to be added in https://github.com/anomalyco/opencode/issues/8463
        exec_agent opencode "$@"
        ;;
    crush)
        exec_agent crush --yolo "$@"
        ;;
    codex)
        exec_agent codex --yolo "$@"
        ;;
    *)
        echo "Unknown AGENT: $AGENT" >&2
        exit 1
        ;;
esac
