#!/bin/bash

# NOTE: no 'set -e' here on purpose — this script must NEVER exit due to a
# child process failing. It supervises services and restarts them forever.

OPENCODE_PORT=${PORT:-8080}
SSH_PORT=2222

if [ "$OPENCODE_PORT" = "$SSH_PORT" ]; then
  OPENCODE_PORT=8080
fi

SSH_USERNAME=${SSH_USERNAME:-root}
SSH_PASSWORD=${SSH_PASSWORD:-}

echo "========================================"
echo "  Railway OpenCode + SSH Setup (Supervised)"
echo "========================================"
echo "OpenCode Port: $OPENCODE_PORT"
echo "SSH Port: $SSH_PORT"
echo "SSH Username: $SSH_USERNAME"
echo ""

# ---------- One-time installation ----------

if ! command -v opencode >/dev/null 2>&1; then
  echo "📥 Installing OpenCode..."
  curl -fsSL https://opencode.ai/install | bash 2>&1 | grep -i "successfully" || true
  export PATH="$HOME/.opencode/bin:$PATH"
  echo "✓ OpenCode installed"
fi

echo ""
echo "🔐 Configuring SSH (password auth)..."

# Ensure OpenCode's persistent data directory exists
# (this should be the Railway Volume mount path so chat history survives redeploys)
mkdir -p /root/.local/share/opencode
echo "✓ OpenCode data directory ready: /root/.local/share/opencode"

SSHD_CONFIG="/etc/ssh/sshd_config"
mkdir -p "$(dirname "$SSHD_CONFIG")"
mkdir -p /run/sshd

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

if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
  echo "  Generating SSH host keys..."
  ssh-keygen -A
fi

if [ -n "$SSH_PASSWORD" ]; then
  echo "root:$SSH_PASSWORD" | chpasswd
  echo "✓ Password set from SSH_PASSWORD variable"
else
  SSH_PASSWORD="changeme123"
  echo "root:$SSH_PASSWORD" | chpasswd
  echo "⚠️  SSH_PASSWORD not set in Railway Variables — using fallback: $SSH_PASSWORD"
fi

export OPENCODE_SERVER_USERNAME="$SSH_USERNAME"
export OPENCODE_SERVER_PASSWORD="$SSH_PASSWORD"

echo ""
echo "========================================"
echo "  🔑 ACCESS CREDENTIALS (same for both)"
echo "========================================"
echo "Username: $SSH_USERNAME"
echo "Password: $SSH_PASSWORD"
echo "========================================"
echo ""

# Make config read-only so accidental edits from an interactive
# terminal session can't break the supervised services.
chmod 444 "$SSHD_CONFIG" 2>/dev/null || true
chmod 555 "$0" 2>/dev/null || true

# ---------- Supervisor loop for SSH ----------
supervise_sshd() {
  while true; do
    if ! pgrep -f "/usr/sbin/sshd -D -f $SSHD_CONFIG" >/dev/null 2>&1; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] Starting sshd..."
      /usr/sbin/sshd -D -f "$SSHD_CONFIG" &
      sleep 2
      if pgrep -f "/usr/sbin/sshd -D -f $SSHD_CONFIG" >/dev/null 2>&1; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] ✓ sshd is up"
      else
        echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] ❌ sshd failed to start, retrying in 5s"
      fi
    fi
    sleep 5
  done
}

# ---------- Supervisor loop for OpenCode ----------
supervise_opencode() {
  while true; do
    NEEDS_RESTART=0

    if ! pgrep -f "opencode web --port $OPENCODE_PORT" >/dev/null 2>&1; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] OpenCode process not found"
      NEEDS_RESTART=1
    else
      # Process exists, but is it actually responding? (catches "zombie" hangs)
      if ! curl -s -o /dev/null -m 5 -w "%{http_code}" "http://127.0.0.1:$OPENCODE_PORT" | grep -qE "^[23]|^401"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] OpenCode process alive but NOT responding (hung) — killing it"
        pkill -9 -f "opencode web --port $OPENCODE_PORT" 2>/dev/null
        sleep 1
        NEEDS_RESTART=1
      fi
    fi

    if [ "$NEEDS_RESTART" = "1" ]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] Starting OpenCode..."
      opencode web --port $OPENCODE_PORT --mdns &
      sleep 3
      if pgrep -f "opencode web --port $OPENCODE_PORT" >/dev/null 2>&1; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] ✓ OpenCode is up"
      else
        echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] ❌ OpenCode failed to start, retrying in 5s"
      fi
    fi

    sleep 5
  done
}

echo "🚀 Starting supervised services..."
echo ""

supervise_sshd &
SUPERVISOR_SSH_PID=$!

supervise_opencode &
SUPERVISOR_OPENCODE_PID=$!

echo "✓ Watchdog for SSH running (supervisor PID: $SUPERVISOR_SSH_PID)"
echo "✓ Watchdog for OpenCode running (supervisor PID: $SUPERVISOR_OPENCODE_PID)"
echo ""
echo "========================================"
echo "  Services Self-Healing & Ready"
echo "========================================"
echo ""
echo "🌐 OpenCode: Check Railway dashboard for domain"
echo "   Login: $SSH_USERNAME / $SSH_PASSWORD"
echo ""
echo "🔑 SSH: Use Railway TCP Proxy (Settings → Networking)"
echo "   ssh $SSH_USERNAME@<proxy-domain> -p <proxy-port>"
echo "   Login: $SSH_USERNAME / $SSH_PASSWORD"
echo ""
echo "ℹ️  If either service crashes or is killed manually,"
echo "   it will be automatically restarted within ~5 seconds."
echo ""

# Keep the container alive forever, watching the supervisors.
# If a supervisor loop itself dies (should never happen), restart it.
while true; do
  if ! kill -0 $SUPERVISOR_SSH_PID 2>/dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] SSH supervisor died, restarting it..."
    supervise_sshd &
    SUPERVISOR_SSH_PID=$!
  fi
  if ! kill -0 $SUPERVISOR_OPENCODE_PID 2>/dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] OpenCode supervisor died, restarting it..."
    supervise_opencode &
    SUPERVISOR_OPENCODE_PID=$!
  fi
  sleep 10
done
