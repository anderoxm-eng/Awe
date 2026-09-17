#!/bin/bash

# NOTE: no 'set -e' here on purpose — this script must NEVER exit due to a
# child process failing. It supervises services and restarts them forever.

FREELLMAPI_PORT=${PORT:-8080}
SSH_PORT=2222

if [ "$FREELLMAPI_PORT" = "$SSH_PORT" ]; then
  FREELLMAPI_PORT=8080
fi

SSH_USERNAME=${SSH_USERNAME:-root}
SSH_PASSWORD=${SSH_PASSWORD:-}

# freellmapi needs an encryption key for at-rest key storage.
# Generate one if not provided via Railway Variables.
if [ -z "$FREELLMAPI_ENCRYPTION_KEY" ]; then
  export FREELLMAPI_ENCRYPTION_KEY=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")
  echo "⚠️  FREELLMAPI_ENCRYPTION_KEY not set — generated a random one for this session."
  echo "    Set it as a Railway Variable to keep your keys across redeploys."
fi

echo "========================================"
echo "  Railway FreeLLMAPI + SSH Setup (Supervised)"
echo "========================================"
echo "FreeLLMAPI Port: $FREELLMAPI_PORT"
echo "SSH Port: $SSH_PORT"
echo "SSH Username: $SSH_USERNAME"
echo ""

# ---------- Data directory ----------
# Mount a Railway Volume here to persist provider keys and analytics across redeploys.
mkdir -p /root/.local/share/freellmapi
echo "✓ FreeLLMAPI data directory ready: /root/.local/share/freellmapi"

# ---------- Write .env for freellmapi ----------
cat > /app/freellmapi/.env << ENVEOF
PORT=$FREELLMAPI_PORT
ENCRYPTION_KEY=$FREELLMAPI_ENCRYPTION_KEY
ENVEOF
echo "✓ .env written"

# ---------- SSH setup ----------
echo ""
echo "🔐 Configuring SSH (password auth)..."

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

echo ""
echo "========================================"
echo "  🔑 ACCESS CREDENTIALS"
echo "========================================"
echo "Dashboard: http://<railway-domain>"
echo "SSH Username: $SSH_USERNAME"
echo "SSH Password: $SSH_PASSWORD"
echo "========================================"
echo ""

chmod 444 "$SSHD_CONFIG" 2>/dev/null || true
chmod 555 "$0" 2>/dev/null || true

# ---------- Supervisor: SSH ----------
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

# ---------- Supervisor: FreeLLMAPI ----------
supervise_freellmapi() {
  while true; do
    NEEDS_RESTART=0

    if ! pgrep -f "node.*dist/index" >/dev/null 2>&1; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] FreeLLMAPI process not found"
      NEEDS_RESTART=1
    else
      HTTP_CODE=$(curl -s -o /dev/null -m 5 -w "%{http_code}" "http://127.0.0.1:$FREELLMAPI_PORT" 2>/dev/null || echo "000")
      if ! echo "$HTTP_CODE" | grep -qE "^[23]|^401"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] FreeLLMAPI alive but NOT responding (code=$HTTP_CODE) — killing it"
        pkill -9 -f "node.*dist/index" 2>/dev/null
        sleep 1
        NEEDS_RESTART=1
      fi
    fi

    if [ "$NEEDS_RESTART" = "1" ]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] Starting FreeLLMAPI on port $FREELLMAPI_PORT..."
      cd /app/freellmapi/server && node dist/index.js &
      sleep 5
      if pgrep -f "node.*dist/index" >/dev/null 2>&1; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] ✓ FreeLLMAPI is up"
      else
        echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] ❌ FreeLLMAPI failed to start, retrying in 5s"
      fi
    fi

    sleep 5
  done
}

echo "🚀 Starting supervised services..."
echo ""

supervise_sshd &
SUPERVISOR_SSH_PID=$!

supervise_freellmapi &
SUPERVISOR_FREELLMAPI_PID=$!

echo "✓ Watchdog for SSH running (supervisor PID: $SUPERVISOR_SSH_PID)"
echo "✓ Watchdog for FreeLLMAPI running (supervisor PID: $SUPERVISOR_FREELLMAPI_PID)"
echo ""
echo "========================================"
echo "  Services Self-Healing & Ready"
echo "========================================"
echo ""
echo "🌐 FreeLLMAPI Dashboard: check Railway dashboard for domain"
echo "   First-time setup: create an account on the dashboard"
echo ""
echo "🔑 SSH: Use Railway TCP Proxy (Settings → Networking)"
echo "   ssh $SSH_USERNAME@<proxy-domain> -p <proxy-port>"
echo "   Password: $SSH_PASSWORD"
echo ""
echo "ℹ️  If either service crashes or is killed manually,"
echo "   it will be automatically restarted within ~5 seconds."
echo ""

# Keep the container alive; restart supervisors if they ever die.
while true; do
  if ! kill -0 $SUPERVISOR_SSH_PID 2>/dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] SSH supervisor died, restarting it..."
    supervise_sshd &
    SUPERVISOR_SSH_PID=$!
  fi
  if ! kill -0 $SUPERVISOR_FREELLMAPI_PID 2>/dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] FreeLLMAPI supervisor died, restarting it..."
    supervise_freellmapi &
    SUPERVISOR_FREELLMAPI_PID=$!
  fi
  sleep 10
done
