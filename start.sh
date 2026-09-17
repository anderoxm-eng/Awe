#!/bin/bash

FREELLMAPI_PORT=${PORT:-3001}
SSH_PORT=2222

if [ "$FREELLMAPI_PORT" = "$SSH_PORT" ]; then
    FREELLMAPI_PORT=3001
fi

SSH_USERNAME=${SSH_USERNAME:-root}
SSH_PASSWORD=${SSH_PASSWORD:-changeme123}

if [ -z "$ENCRYPTION_KEY" ]; then
    export ENCRYPTION_KEY=$(node -e \
        "console.log(require('crypto').randomBytes(32).toString('hex'))")

    echo "⚠️ ENCRYPTION_KEY not set — generated for this session."
fi

echo "========================================"
echo "  Railway FreeLLMAPI + SSH Setup"
echo "========================================"
echo "FreeLLMAPI Port: $FREELLMAPI_PORT"
echo "SSH Port: $SSH_PORT"
echo ""

# ---------- SSH configuration ----------

SSHD_CONFIG="/etc/ssh/sshd_config"

mkdir -p /run/sshd
mkdir -p /etc/ssh

cat > "$SSHD_CONFIG" << SSHEOF
Port $SSH_PORT
PermitRootLogin yes
PasswordAuthentication yes
PermitEmptyPasswords no
UsePAM no
X11Forwarding no
PrintMotd no
Subsystem sftp /usr/lib/openssh/sftp-server
SSHEOF

# Verify SSH host keys
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    echo "Generating SSH host keys..."
    ssh-keygen -A
fi

# Set SSH password
echo "root:$SSH_PASSWORD" | chpasswd

echo "✓ SSH password configured"

# Validate SSH configuration
if ! /usr/sbin/sshd -t -f "$SSHD_CONFIG"; then
    echo "❌ SSH configuration is invalid"
    exit 1
fi

echo "✓ SSH configuration validated"

# ---------- SSH supervisor ----------

supervise_sshd() {
    while true; do
        if ! pgrep -f "sshd -D -f $SSHD_CONFIG" >/dev/null 2>&1; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') [SSH] Starting sshd..."

            /usr/sbin/sshd -D -f "$SSHD_CONFIG" &

            sleep 2

            if pgrep -f "sshd -D -f $SSHD_CONFIG" >/dev/null 2>&1; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') [SSH] ✓ SSH is running"
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') [SSH] ❌ SSH failed"
            fi
        fi

        sleep 5
    done
}

# ---------- Start SSH ----------

echo "🚀 Starting SSH supervisor..."

supervise_sshd &
SSH_SUPERVISOR_PID=$!

echo "✓ SSH supervisor PID: $SSH_SUPERVISOR_PID"

# ---------- Start FreeLLMAPI ----------

echo ""
echo "========================================"
echo "  Starting FreeLLMAPI"
echo "========================================"
echo "Port: $FREELLMAPI_PORT"
echo "Watchdog: DISABLED for diagnostic testing"
echo ""

# Check application files
if [ ! -f /app/server/dist/index.js ]; then
    echo "❌ FreeLLMAPI entry file not found:"
    echo "/app/server/dist/index.js"
    exit 1
fi

echo "✓ FreeLLMAPI entry file found"
echo "🚀 Launching FreeLLMAPI..."
echo ""

# Run FreeLLMAPI as the main process.
# No pkill, no HTTP health check, no automatic restart.
exec env PORT="$FREELLMAPI_PORT" \
    node --max-old-space-size=256 \
    /app/server/dist/index.js