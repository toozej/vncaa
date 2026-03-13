# OliveTin vncaa Control

This directory contains files for controlling vncaa Docker Compose projects on a remote server (oracle) via OliveTin actions.

## Components

| File | Purpose |
|------|---------|
| `config.yaml` | OliveTin action configuration |
| `start_vncaa` | Script to start vncaa Docker Compose project |
| `stop_vncaa` | Script to stop vncaa Docker Compose project |
| `vncaa_command_wrapper` | SSH command validator and logger |
| `ssh_authorized_keys_entry` | Template for SSH authorized_keys entry |

## Architecture

```
┌─────────────────┐       SSH       ┌─────────────────┐
│   OliveTin      │ ─────────────── │   Oracle        │
│   (container)   │                 │   (server)      │
│                 │                 │                 │
│  config.yaml    │                 │  vncaa_command_ │
│  SSH key        │                 │  wrapper     │
│                 │                 │       ↓         │
│                 │                 │  start_vncaa │
│                 │                 │  stop_vncaa  │
│                 │                 │       ↓         │
│                 │                 │  Docker Compose │
└─────────────────┘                 └─────────────────┘
```

## Installation

### Step 1: Install Scripts on Oracle Server

```bash
# Copy scripts to oracle server
scp start_vncaa stop_vncaa vncaa_command_wrapper oracle:/tmp/

# SSH to oracle and install
ssh oracle << 'EOF'
  sudo cp /tmp/start_vncaa /tmp/stop_vncaa /tmp/vncaa_command_wrapper /usr/local/bin/
  sudo chmod +x /usr/local/bin/start_vncaa /usr/local/bin/stop_vncaa /usr/local/bin/vncaa_command_wrapper
  
  # Create log file with appropriate permissions
  sudo touch /var/log/vncaa_commands.log
  sudo chmod 666 /var/log/vncaa_commands.log
  
  # Optional: Set up log rotation
  sudo tee /etc/logrotate.d/vncaa_commands > /dev/null << 'LOGROTATE'
/var/log/vncaa_commands.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    create 0666 root root
}
LOGROTATE
```

### Step 2: Create Directory Structure on Oracle Server

```bash
ssh oracle << 'EOF'
  # Create vncaa project directories (example for claude, gemini, etc.)
  mkdir -p ~/docker/vncaa-claude
  mkdir -p ~/docker/vncaa-gemini
  mkdir -p ~/docker/vncaa-kilocode
  # ... create others as needed
EOF
```

### Step 3: Generate SSH Key Pair

On the machine running OliveTin (or your local machine for initial setup):

```bash
# Generate a dedicated SSH key for vncaa automation
ssh-keygen -t ed25519 -f ./vncaa_oracle -C "vncaa-automation" -N ""

# This creates:
#   ./vncaa_oracle       (private key - keep secure!)
#   ./vncaa_oracle.pub   (public key - copy to oracle server)
```

### Step 4: Configure SSH Authorized Keys on Oracle Server

The `command=` directive in authorized_keys forces all SSH connections using this key to run through the wrapper script. This is the security mechanism that restricts what commands can be executed.

**How it works:**

1. When OliveTin connects via SSH using this key, SSH forces `vncaa_command_wrapper` to run
2. The wrapper receives the original command in the `SSH_ORIGINAL_COMMAND` environment variable
3. The wrapper validates the command against the allowed scripts list
4. If valid, it executes the script; if not, it denies the request

**Add to authorized_keys on oracle server:**

```bash
# On oracle server, edit ~/.ssh/authorized_keys
# Add this single line (replace <PUBLIC_KEY> with contents of vncaa_oracle.pub):

command="/usr/local/bin/vncaa_command_wrapper",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... vncaa-automation
```

**Example with actual public key:**

```bash
# Copy the public key
PUB_KEY=$(cat vncaa_oracle.pub | cut -d' ' -f2-)

# Add to authorized_keys on oracle
ssh oracle "echo 'command=\"/usr/local/bin/vncaa_command_wrapper\",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ${PUB_KEY}' >> ~/.ssh/authorized_keys"
```

**Understanding the authorized_keys options:**

| Option | Purpose |
|--------|---------|
| `command="..."` | Forces execution of this script, ignores user's requested command |
| `no-port-forwarding` | Prevents SSH port forwarding (-L, -R) |
| `no-X11-forwarding` | Prevents X11 GUI forwarding |
| `no-agent-forwarding` | Prevents SSH agent forwarding |
| `no-pty` | Prevents interactive shell allocation |

### Step 5: Configure OliveTin

```bash
# Copy the OliveTin config
cp config.yaml /path/to/olivetin/config.yaml

# Create SSH config directory in OliveTin container
mkdir -p /path/to/olivetin/ssh

# Copy the private key
cp vncaa_oracle /path/to/olivetin/ssh/vncaa_oracle
chmod 600 /path/to/olivetin/ssh/vncaa_oracle

# Create SSH config file
cat > /path/to/olivetin/ssh/config << 'EOF'
Host oracle
    HostName oracle.example.com
    User your-username
    IdentityFile /config/ssh/vncaa_oracle
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
```

### Step 6: Docker Compose for OliveTin (Optional)

If running OliveTin in Docker:

```yaml
services:
  olivetin:
    image: jamesread/olivetin
    container_name: olivetin
    volumes:
      - ./config.yaml:/config/config.yaml:ro
      - ./ssh:/config/ssh:ro
    ports:
      - "1337:1337"
    restart: unless-stopped
```

## Usage

### Via OliveTin Web UI

1. Open OliveTin web interface (default: http://localhost:1337)
2. Click "Start vncaa" or "Stop vncaa"
3. Select LLM Agent from dropdown (Claude, Gemini, Kilocode, etc.)
4. Optionally enter:
   - Working Directory: Path to mount as workspace
   - Repository: Git URL to clone
   - Branch: Git branch to checkout
5. Click "Start"

### Via Command Line (Testing)

```bash
# Test the SSH connection and wrapper
ssh -i vncaa_oracle oracle

# You should see:
# Allowed commands:
#   /usr/local/bin/start_vncaa
#   /usr/local/bin/stop_vncaa

# Test starting vncaa
ssh -i vncaa_oracle oracle "/usr/local/bin/start_vncaa claude /workspace https://github.com/user/repo.git main"

# Test stopping vncaa
ssh -i vncaa_oracle oracle "/usr/local/bin/stop_vncaa claude"

# These will be denied:
ssh -i vncaa_oracle oracle "ls"              # Denied
ssh -i vncaa_oracle oracle "/bin/bash"       # Denied
ssh -i vncaa_oracle oracle "cat /etc/passwd" # Denied
```

### Environment Variable Logic

The start script sets environment variables based on provided arguments:

| Arguments Provided | Environment Variables Set |
|-------------------|--------------------------|
| Working Directory only | `WORKSPACE_PATH=<dir>`, `WORKSPACE_MODE=mount` |
| Repo + Branch only | `WORKSPACE_REPO=<repo>`, `WORKSPACE_REF=<branch>`, `WORKSPACE_MODE=checkout` |
| Both | Repo/Branch take precedence, `WORKSPACE_MODE=checkout` |
| None | No workspace environment variables set |

## Project Directory Structure

vncaa projects must exist in `~/docker/vncaa-${LLM_AGENT}` on the oracle server (the omnibus image includes all language toolchains):

```
~/docker/
├── vncaa-claude/
│   └── docker-compose.yaml
├── vncaa-gemini/
│   └── docker-compose.yaml
├── vncaa-kilocode/
│   └── docker-compose.yaml
└── ...
```

## Logging

All command attempts are logged to `/var/log/vncaa_commands.log` on the oracle server:

```bash
# View logs
tail -f /var/log/vncaa_commands.log

# Example output:
# [2024-01-15 10:30:22] user=ubuntu ip=192.168.1.100 status=EXECUTING command="/usr/local/bin/start_vncaa" args="start_vncaa claude"
# [2024-01-15 10:31:45] user=ubuntu ip=192.168.1.100 status=DENIED command="/bin/ls" args="/bin/ls"
```

Log status values:
- `EXECUTING` - Command allowed and running
- `DENIED` - Command not in allowed list
- `NOT_FOUND` - Script doesn't exist or isn't executable
- `INJECTION_BLOCKED` - Shell metacharacters detected in arguments

## Security Notes

1. **Key Security**: The `vncaa_oracle` private key should be protected and only accessible to OliveTin
2. **No Shell Access**: The `no-pty` and `command=` restrictions prevent interactive shell access
3. **Command Whitelist**: Only `start_vncaa` and `stop_vncaa` can be executed
4. **Injection Protection**: The wrapper blocks shell metacharacters (`;`, `|`, `&`, `$`, backticks, etc.)
5. **Audit Logging**: All attempts (successful and denied) are logged

## Troubleshooting

### SSH Connection Refused

```bash
# Verify SSH service is running on oracle
ssh oracle "systemctl status sshd"

# Check firewall allows SSH
ssh oracle "sudo ufw status"
```

### Permission Denied

```bash
# Verify the SSH key is correct
ssh -v -i vncaa_oracle oracle

# Check authorized_keys permissions
ssh oracle "ls -la ~/.ssh/authorized_keys"
# Should be: -rw------- (600)
```

### Script Not Found

```bash
# Verify scripts exist and are executable
ssh oracle "ls -la /usr/local/bin/*vncaa*"
```

### Command Not Allowed

```bash
# Check the wrapper log
ssh oracle "cat /var/log/vncaa_commands.log"

# Verify wrapper is executable
ssh oracle "test -x /usr/local/bin/vncaa_command_wrapper && echo 'OK' || echo 'Not executable'"
```

### Docker Compose Issues

```bash
# Check if Docker Compose project exists
ssh oracle "ls -la ~/docker/vncaa-claude/"

# Manually test docker compose
ssh oracle "cd ~/docker/vncaa-claude && docker compose config"
```
