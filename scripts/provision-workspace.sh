#!/bin/bash
set -euo pipefail

# Workspace provisioning helper for vncaa
# Supports two modes:
#  1) mount: use the mounted /repo directory as-is (default)
#  2) checkout: clone a repository into a unique subdirectory under /repo/.vncaa-checkouts
#
# Environment variables:
#  - WORKSPACE_MODE: "mount" or "checkout" (default: "mount")
#  - WORKSPACE_REPO: repository to clone (e.g., "owner/repo" or full URL) when checkout
#  - WORKSPACE_REF: branch/tag/commit to checkout (optional; defaults to default branch)
#  - WORKSPACE_BASE: base mount path (default: "/repo")
#  - WORKSPACE_TMP_BASE: base for unique checkout dirs (default: "/repo/.vncaa-checkouts")
#  - WORKSPACE_CLEANUP: if "1", remove temp checkout dir only if it was created by this script (safe cleanup)
#  - GH_TOKEN: optional GitHub token for private repos (prefer host-mounted gh config)
#
# Output:
#  - WORKSPACE_PATH: absolute path to the workspace (either /repo or a unique checkout subdir)
#  - WORKSPACE_TEMP_DIR: if checkout, the unique temp directory created

WORKSPACE_MODE=${WORKSPACE_MODE:-mount}
WORKSPACE_REPO=${WORKSPACE_REPO:-}
WORKSPACE_REF=${WORKSPACE_REF:-}
WORKSPACE_BASE=${WORKSPACE_BASE:-/repo}
WORKSPACE_TMP_BASE=${WORKSPACE_TMP_BASE:-/repo/.vncaa-checkouts}
WORKSPACE_CLEANUP=${WORKSPACE_CLEANUP:-1}

# Validate mode
if [[ "$WORKSPACE_MODE" != "mount" && "$WORKSPACE_MODE" != "checkout" ]]; then
  echo "ERROR: WORKSPACE_MODE must be 'mount' or 'checkout'" >&2
  exit 1
fi

# Mount mode: use base as-is
if [[ "$WORKSPACE_MODE" == "mount" ]]; then
  WORKSPACE_PATH="$WORKSPACE_BASE"
  echo "Using mounted workspace: $WORKSPACE_PATH"
  export WORKSPACE_PATH
  exit 0
fi

# Checkout mode: validate repo
if [[ -z "$WORKSPACE_REPO" ]]; then
  echo "ERROR: WORKSPACE_REPO must be set for checkout mode" >&2
  exit 1
fi

# Create temp base if needed
if [[ ! -d "$WORKSPACE_TMP_BASE" ]]; then
  mkdir -p "$WORKSPACE_TMP_BASE"
fi

# Create a unique temp directory for this checkout
WORKSPACE_TEMP_DIR=$(mktemp -d "$WORKSPACE_TMP_BASE/XXXXXX")
WORKSPACE_PATH="$WORKSPACE_TEMP_DIR"

echo "Cloning $WORKSPACE_REPO into $WORKSPACE_PATH"

# Try GitHub CLI first (prefers host-mounted gh config)
if command -v gh >/dev/null 2>&1; then
  GH_ARGS=()
  if [[ -n "$WORKSPACE_REF" ]]; then
    GH_ARGS+=("--branch" "$WORKSPACE_REF")
  fi
  if [[ -n "$GH_TOKEN" ]]; then
    GH_ARGS+=("--env" "GH_TOKEN=$GH_TOKEN")
  fi
  if gh repo clone "$WORKSPACE_REPO" "$WORKSPACE_TEMP_DIR" "${GH_ARGS[@]}"; then
    echo "Cloned via gh CLI"
  else
    echo "gh clone failed, falling back to git"
    git clone --depth 1 "https://github.com/$WORKSPACE_REPO.git" "$WORKSPACE_TEMP_DIR"
    if [[ -n "$WORKSPACE_REF" ]]; then
      git -C "$WORKSPACE_TEMP_DIR" checkout "$WORKSPACE_REF"
    fi
  fi
else
  # Fallback to git with SSH if available
  if [[ -d "/tmp/host-ssh" ]]; then
    GIT_SSH_COMMAND='ssh -i /tmp/host-ssh/id_rsa -o IdentitiesOnly=yes' git clone --depth 1 "git@github.com:$WORKSPACE_REPO.git" "$WORKSPACE_TEMP_DIR"
  else
    git clone --depth 1 "https://github.com/$WORKSPACE_REPO.git" "$WORKSPACE_TEMP_DIR"
  fi
  if [[ -n "$WORKSPACE_REF" ]]; then
    git -C "$WORKSPACE_TEMP_DIR" checkout "$WORKSPACE_REF"
  fi
fi

# Export paths
export WORKSPACE_PATH

echo "Workspace ready at: $WORKSPACE_PATH"
