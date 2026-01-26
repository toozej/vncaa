#!/bin/bash
set -e

AGENT=${AGENT:-claude}

# Allow passwordless su to root
passwd -d root

# Create user with host UID/GID
HOST_UID="${HOST_UID:-1000}"
HOST_GID="${HOST_GID:-1000}"
HOST_USER="${HOST_USER:-vncuser}"

echo "Creating user $HOST_USER with UID=$HOST_UID GID=$HOST_GID"

# Create group if it doesn't exist
groupadd -g "$HOST_GID" "$HOST_USER" 2>/dev/null || true

# Create user if it doesn't exist
useradd -m -u "$HOST_UID" -g "$HOST_GID" -s /bin/bash "$HOST_USER" 2>/dev/null || true

USER_HOME="/home/$HOST_USER"

# Provision workspace (mount or checkout) before copying configs
# This ensures WORKSPACE_PATH is available for agent execution
if [ -f /app/scripts/provision-workspace.sh ]; then
  echo "Provisioning workspace..."
  source /app/scripts/provision-workspace.sh
  WORKSPACE_PATH=${WORKSPACE_PATH:-/repo}
  echo "Workspace path: $WORKSPACE_PATH"
else
  WORKSPACE_PATH=/repo
fi

# Copy config files to user's home
# setup gitconfig
if [ -f /tmp/host-gitconfig ]; then
    cp /tmp/host-gitconfig "$USER_HOME/.gitconfig"
    chown "$HOST_UID:$HOST_GID" "$USER_HOME/.gitconfig"
fi

# setup SSH config
if [ -d /tmp/host-ssh ]; then
    cp -r /tmp/host-ssh "$USER_HOME/.ssh"
    chown -R "$HOST_UID:$HOST_GID" "$USER_HOME/.ssh"
    chmod 700 "$USER_HOME/.ssh"
    chmod 600 "$USER_HOME/.ssh"/* 2>/dev/null || true
fi

# setup GH CLI config
if [ -d /tmp/host-gh-config ]; then
    mkdir -p "$USER_HOME/.config"
    chown "$HOST_UID:$HOST_GID" "$USER_HOME/.config"
    ln -sf /tmp/host-gh-config "$USER_HOME/.config/gh"
    chown -h "$HOST_UID:$HOST_GID" "$USER_HOME/.config/gh"
    echo "Symlinked $USER_HOME/.config/gh -> /tmp/host-gh-config"
fi

# Symlink agent-specific configs
case "$AGENT" in
    claude)
        # Use symlinks so claude can read/write directly to host configs
        # ~/.claude for session data
        if [ -d /tmp/host-claude ]; then
            ln -sf /tmp/host-claude "$USER_HOME/.claude"
            chown -h "$HOST_UID:$HOST_GID" "$USER_HOME/.claude"
            echo "Symlinked $USER_HOME/.claude -> /tmp/host-claude"
        fi
        # ~/.claude.json for credentials
        if [ -f /tmp/host-claude.json ]; then
            ln -sf /tmp/host-claude.json "$USER_HOME/.claude.json"
            chown "$HOST_UID:$HOST_GID" "$USER_HOME/.claude.json"
            echo "Symlinked $USER_HOME/.claude.json -> /tmp/host-claude.json"
        fi
        # ~/.config/claude for additional config
        if [ -d /tmp/host-claude-config ]; then
            mkdir -p "$USER_HOME/.config"
            chown "$HOST_UID:$HOST_GID" "$USER_HOME/.config"
            ln -sf /tmp/host-claude-config "$USER_HOME/.config/claude"
            chown -h "$HOST_UID:$HOST_GID" "$USER_HOME/.config/claude"
            echo "Symlinked $USER_HOME/.config/claude -> /tmp/host-claude-config"
        fi
        ;;
    gemini)
        # ~/.gemini for session data
        if [ -d /tmp/host-gemini ]; then
            ln -sf /tmp/host-gemini "$USER_HOME/.gemini"
            chown -h "$HOST_UID:$HOST_GID" "$USER_HOME/.gemini"
            echo "Symlinked $USER_HOME/.gemini -> /tmp/host-gemini"
        fi
        ;;
    kilocode)
        # ~/.kilocode for session data
        if [ -d /tmp/host-kilocode ]; then
            ln -sf /tmp/host-kilocode "$USER_HOME/.kilocode"
            chown -h "$HOST_UID:$HOST_GID" "$USER_HOME/.kilocode"
            echo "Symlinked $USER_HOME/.kilocode -> /tmp/host-kilocode"
        fi
        ;;
    opencode)
        # ~/.config/opencode for config
        if [ -d /tmp/host-opencode-config ]; then
            mkdir -p "$USER_HOME/.config"
            chown "$HOST_UID:$HOST_GID" "$USER_HOME/.config"
            ln -sf /tmp/host-opencode-config "$USER_HOME/.config/opencode"
            chown -h "$HOST_UID:$HOST_GID" "$USER_HOME/.config/opencode"
            echo "Symlinked $USER_HOME/.config/opencode -> /tmp/host-opencode-config"
        fi
        # ~/.opencode for session data
        if [ -d /tmp/host-opencode ]; then
            ln -sf /tmp/host-opencode "$USER_HOME/.opencode"
            chown -h "$HOST_UID:$HOST_GID" "$USER_HOME/.opencode"
            echo "Symlinked $USER_HOME/.opencode -> /tmp/host-opencode"
        fi
        # Custom config file via OPENCODE_CONFIG
        if [ -f /tmp/host-opencode-file ]; then
            if [ -n "$OPENCODE_CONFIG" ]; then
                mkdir -p "$(dirname "$OPENCODE_CONFIG")"
                ln -sf /tmp/host-opencode-file "$OPENCODE_CONFIG"
                chown -h "$HOST_UID:$HOST_GID" "$OPENCODE_CONFIG"
                echo "Symlinked $OPENCODE_CONFIG -> /tmp/host-opencode-file"
            fi
        fi
        ;;
    crush)
        # ~/.config/crush for config
        if [ -d /tmp/host-crush-config ]; then
            mkdir -p "$USER_HOME/.config/crush"
            chown "$HOST_UID:$HOST_GID" "$USER_HOME/.config/crush"
            ln -sf /tmp/host-crush-config "$USER_HOME/.config/crush"
            chown -h "$HOST_UID:$HOST_GID" "$USER_HOME/.config/crush"
            echo "Symlinked $USER_HOME/.config/crush -> /tmp/host-crush-config"
        fi
        ;;
    codex)
        # ~/.codex for user config
        if [ -d /tmp/host-codex ]; then
            ln -sf /tmp/host-codex "$USER_HOME/.codex"
            chown -h "$HOST_UID:$HOST_GID" "$USER_HOME/.codex"
            echo "Symlinked $USER_HOME/.codex -> /tmp/host-codex"
        fi
        ;;
esac

# Copy alacritty config
mkdir -p "$USER_HOME/.config/alacritty"
cp /app/alacritty.toml "$USER_HOME/.config/alacritty/alacritty.toml"
chown -R "$HOST_UID:$HOST_GID" "$USER_HOME/.config/alacritty"

# Bash configuration
cat >> "$USER_HOME/.bashrc" << BASHRC
# Bash configuration
export PATH="/usr/local/bin:/usr/bin:/bin:\$PATH"
BASHRC
chown "$HOST_UID:$HOST_GID" "$USER_HOME/.bashrc"

# Use 'su' without '-' to preserve more environment, but still set critical vars
# Pass WORKSPACE_PATH to vnccc so it can use the correct workspace
exec su "$HOST_USER" -c "export HOME=$USER_HOME && export PATH=/usr/local/bin:/usr/bin:/bin:\$PATH && export WORKSPACE_PATH=$WORKSPACE_PATH && /usr/local/bin/vnccc $*"
