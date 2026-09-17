#!/bin/bash

# ⚠️ عمداً از 'set -e' استفاده نمی‌کنیم — این اسکریپت نباید به خاطر خطای یک فرآیند فرزند متوقف شود.

OPENCODE_PORT=${PORT:-8080}
SSH_PORT=2222

if [ "$OPENCODE_PORT" = "$SSH_PORT" ]; then
  OPENCODE_PORT=8080
fi

SSH_USERNAME=${SSH_USERNAME:-root}
SSH_PASSWORD=${SSH_PASSWORD:-}

echo "========================================"
echo "  Railway FreeLLMAPI Server + SSH"
echo "========================================"
echo "FreeLLMAPI Port: $OPENCODE_PORT"
echo "SSH Port: $SSH_PORT"
echo ""

# ---------- نصب یک‌باره سرور FreeLLMAPI از سورس ----------
FREELMAPI_DIR="/app/freellmapi-server"

if [ ! -d "$FREELMAPI_DIR" ]; then
  echo "📥 Cloning FreeLLMAPI server from source..."
  git clone https://github.com/tashfeenahmed/freellmapi.git "$FREELMAPI_DIR"
  cd "$FREELMAPI_DIR"

  echo "📦 Installing dependencies (this may take a few minutes)..."
  npm install --no-audit --no-fund

  echo "🔨 Building server and dashboard..."
  npm run build
  echo "✓ FreeLLMAPI server built successfully"
else
  echo "✓ FreeLLMAPI server already present at $FREELMAPI_DIR"
fi

# تولید ENCRYPTION_KEY در صورت نبود
if [ -z "$ENCRYPTION_KEY" ]; then
  export ENCRYPTION_KEY=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")
  echo "⚠️  Generated temporary ENCRYPTION_KEY. Set it in Railway Variables for persistence."
fi

# ---------- پیکربندی SSH ----------
echo ""
echo "🔐 Configuring SSH..."
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
  echo "⚠️  SSH_PASSWORD not set — using fallback: $SSH_PASSWORD"
fi

echo ""
echo "========================================"
echo "  🔑 ACCESS CREDENTIALS"
echo "========================================"
echo "Username: $SSH_USERNAME"
echo "Password: $SSH_PASSWORD"
echo "========================================"

# ---------- Supervisor Loop for SSH ----------
supervise_sshd() {
  while true; do
    if ! pgrep -f "/usr/sbin/sshd -D -f $SSHD_CONFIG" >/dev/null 2>&1; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] Starting sshd..."
      /usr/sbin/sshd -D -f "$SSHD_CONFIG" &
      sleep 2
      if pgrep -f "/usr/sbin/sshd -D -f $SSHD_CONFIG" >/dev/null 2>&1; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] ✓ sshd is up"
      fi
    fi
    sleep 5
  done
}

# ---------- Supervisor Loop for FreeLLMAPI Server ----------
supervise_freellmapi() {
  while true; do
    NEEDS_RESTART=0

    # بررسی وجود فرآیند سرور (node server/dist/index.js)
    if ! pgrep -f "node.*server/dist/index.js" >/dev/null 2>&1; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] FreeLLMAPI server process not found"
      NEEDS_RESTART=1
    else
      # بررسی پاسخگویی سرویس روی پورت مورد نظر
      if ! curl -s -o /dev/null -m 5 -w "%{http_code}" "http://127.0.0.1:$OPENCODE_PORT/api/ping" | grep -qE "^[23]"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] FreeLLMAPI alive but NOT responding — killing"
        pkill -9 -f "node.*server/dist/index.js" 2>/dev/null
        sleep 1
        NEEDS_RESTART=1
      fi
    fi

    if [ "$NEEDS_RESTART" = "1" ]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] Starting FreeLLMAPI server..."
      
      # اجرای سرور روی پورت Railway
      cd "$FREELMAPI_DIR" && \
        PORT=$OPENCODE_PORT \
        HOST_BIND=0.0.0.0 \
        ENCRYPTION_KEY="$ENCRYPTION_KEY" \
        node server/dist/index.js &
      
      sleep 5
      if pgrep -f "node.*server/dist/index.js" >/dev/null 2>&1; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] ✓ FreeLLMAPI server is up on port $OPENCODE_PORT"
      else
        echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] ❌ FreeLLMAPI failed to start, retrying in 10s"
        sleep 10
      fi
    fi

    sleep 10
  done
}

echo ""
echo "🚀 Starting supervised services..."
supervise_sshd &
SUPERVISOR_SSH_PID=$!

supervise_freellmapi &
SUPERVISOR_FREELLMAPI_PID=$!

echo "✓ Watchdog for SSH running (PID: $SUPERVISOR_SSH_PID)"
echo "✓ Watchdog for FreeLLMAPI running (PID: $SUPERVISOR_FREELLMAPI_PID)"
echo ""
echo "========================================"
echo "  Services Self-Healing & Ready"
echo "========================================"
echo ""
echo "🌐 FreeLLMAPI Dashboard: Check Railway dashboard for domain"
echo "   Then visit: https://<your-railway-domain>"
echo ""
echo "🔑 SSH: Use Railway TCP Proxy (Settings → Networking)"
echo "   ssh $SSH_USERNAME@<proxy-domain> -p <proxy-port>"
echo ""
echo "ℹ️  If either service crashes, it will be automatically restarted within ~10 seconds."
echo ""

# حلقه اصلی نگهبان
while true; do
  if ! kill -0 $SUPERVISOR_SSH_PID 2>/dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] SSH supervisor died, restarting..."
    supervise_sshd &
    SUPERVISOR_SSH_PID=$!
  fi
  if ! kill -0 $SUPERVISOR_FREELLMAPI_PID 2>/dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] FreeLLMAPI supervisor died, restarting..."
    supervise_freellmapi &
    SUPERVISOR_FREELLMAPI_PID=$!
  fi
  sleep 10
done