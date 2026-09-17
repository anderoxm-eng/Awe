#!/bin/bash

FREELLMAPI_PORT=${PORT:-3001}
SSH_PORT=2222

if [ "$FREELLMAPI_PORT" = "$SSH_PORT" ]; then
  FREELLMAPI_PORT=3001
fi

SSH_USERNAME=${SSH_USERNAME:-root}
SSH_PASSWORD=${SSH_PASSWORD:-changeme123}

if [ -z "$ENCRYPTION_KEY" ]; then
  export ENCRYPTION_KEY=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")
  echo "⚠️  ENCRYPTION_KEY not set — generated a random one for this session."
  echo "    Set it as a Railway Variable to keep your keys across redeploys."
fi

echo "========================================"
echo "  Railway FreeLLMAPI + SSH Setup"
echo "========================================"
echo "FreeLLMAPI Port: $FREELLMAPI_PORT"
echo "SSH Port: $SSH_PORT"
echo "SSH Username: $SSH_USERNAME"
echo ""

# ---------- SSH config (same approach as original start.sh) ----------
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

# Host keys were generated in Dockerfile build step — just verify
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
  echo "  Generating SSH host keys..."
  ssh-keygen -A
fi

# Set root password — /etc/shadow was made writable in Dockerfile
echo "root:$SSH_PASSWORD" | chpasswd
echo "✓ Password set"

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

# ---------- Supervisor: SSH ----------
supervise_sshd() {
  while true; do
    if ! pgrep -f "/usr/sbin/sshd -D -f $SSHD_CONFIG" >/dev/null 2>&1; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] Starting sshd..."
      /usr/sbin/sshd -D -f "$SSHD_CONFIG" &
      sleep 2
      pgrep -f "/usr/sbin/sshd -D -f $SSHD_CONFIG" >/dev/null 2>&1 \
        && echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] ✓ sshd is up" \
        || echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] ❌ sshd failed"
    fi
    sleep 5
  done
}

# ---------- Supervisor: FreeLLMAPI ----------
# --max-old-space-size=256 prevents OOM kill on Railway's free tier (512MB RAM)
supervise_freellmapi() {
  while true; do
    NEEDS_RESTART=0
    if ! pgrep -f "node.*server/dist/index" >/dev/null 2>&1; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] FreeLLMAPI process not found"
      NEEDS_RESTART=1
    else
      HTTP_CODE=$(curl -s -o /dev/null -m 5 -w "%{http_code}" "http://127.0.0.1:$FREELLMAPI_PORT" 2>/dev/null || echo "000")
      if ! echo "$HTTP_CODE" | grep -qE "^[23]|^401"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] FreeLLMAPI not responding (code=$HTTP_CODE) — restarting"
        pkill -9 -f "node.*server/dist/index" 2>/dev/null
        sleep 1
        NEEDS_RESTART=1
      fi
    fi

    if [ "$NEEDS_RESTART" = "1" ]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] Starting FreeLLMAPI on port $FREELLMAPI_PORT..."
      PORT=$FREELLMAPI_PORT node --max-old-space-size=256 /app/server/dist/index.js &
      sleep 5
      pgrep -f "node.*server/dist/index" >/dev/null 2>&1 \
        && echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] ✓ FreeLLMAPI is up" \
        || echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] ❌ FreeLLMAPI failed to start"
    fi
    sleep 5
  done
}

echo "🚀 Starting supervised services..."
supervise_sshd &
SUPERVISOR_SSH_PID=$!
supervise_freellmapi &
SUPERVISOR_FREELLMAPI_PID=$!

echo "✓ SSH watchdog PID: $SUPERVISOR_SSH_PID"
echo "✓ FreeLLMAPI watchdog PID: $SUPERVISOR_FREELLMAPI_PID"
echo ""
echo "🌐 Dashboard: Railway domain → http://<domain>"
echo "🔑 SSH: Railway TCP Proxy (Settings → Networking) → port $SSH_PORT"
echo ""

while true; do
  if ! kill -0 $SUPERVISOR_SSH_PID 2>/dev/null; then
    supervise_sshd & SUPERVISOR_SSH_PID=$!
  fi
  if ! kill -0 $SUPERVISOR_FREELLMAPI_PID 2>/dev/null; then
    supervise_freellmapi & SUPERVISOR_FREELLMAPI_PID=$!
  fi
  sleep 10
done
