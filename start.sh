#!/bin/bash

# اسکریپت نظارت بر سرویس‌ها برای Railway
# جایگزینی OpenCode با FreeLLMAPI

OPENCODE_PORT=${PORT:-8080}  # در Railway از متغیر PORT استفاده می‌شود
SSH_PORT=2222

if [ "$OPENCODE_PORT" = "$SSH_PORT" ]; then
  OPENCODE_PORT=8080
fi

SSH_USERNAME=${SSH_USERNAME:-root}
SSH_PASSWORD=${SSH_PASSWORD:-}

echo "========================================"
echo "  Railway FreeLLMAPI + SSH (Supervised)"
echo "========================================"
echo "FreeLLMAPI Port: $OPENCODE_PORT"
echo "SSH Port: $SSH_PORT"
echo ""

# ---------- پیکربندی SSH ----------
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
  echo "✓ Password set from SSH_PASSWORD"
else
  SSH_PASSWORD="changeme123"
  echo "root:$SSH_PASSWORD" | chpasswd
  echo "⚠️  SSH_PASSWORD not set, using fallback: $SSH_PASSWORD"
fi

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

# ---------- Supervisor Loop for FreeLLMAPI ----------
supervise_freellmapi() {
  while true; do
    NEEDS_RESTART=0

    # بررسی وجود فرآیند FreeLLMAPI
    if ! pgrep -f "freellmapi" >/dev/null 2>&1; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] FreeLLMAPI process not found"
      NEEDS_RESTART=1
    else
      # بررسی پاسخگویی سرویس روی پورت مورد نظر
      if ! curl -s -o /dev/null -m 5 -w "%{http_code}" "http://127.0.0.1:$OPENCODE_PORT" | grep -qE "^[23]|^401"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] FreeLLMAPI alive but NOT responding — killing"
        pkill -9 -f "freellmapi" 2>/dev/null
        sleep 1
        NEEDS_RESTART=1
      fi
    fi

    if [ "$NEEDS_RESTART" = "1" ]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] Starting FreeLLMAPI..."
      
      # اجرای سرور FreeLLMAPI روی پورت مشخص شده
      # نکته: از ENCRYPTION_KEY که در متغیرهای محیطی تنظیم کرده‌اید استفاده می‌کند
      # در غیر این صورت یک کلید موقت تولید می‌کند که با ری‌استارت از بین می‌رود.
      if [ -z "$ENCRYPTION_KEY" ]; then
        export ENCRYPTION_KEY=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")
        echo "⚠️  Generated temporary ENCRYPTION_KEY. Set it in Railway Variables for persistence."
      fi

      # اجرای دستور اصلی سرور
      PORT=$OPENCODE_PORT ENCRYPTION_KEY="$ENCRYPTION_KEY" freellmapi &
      
      sleep 5
      if pgrep -f "freellmapi" >/dev/null 2>&1; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] ✓ FreeLLMAPI is up on port $OPENCODE_PORT"
      else
        echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] ❌ FreeLLMAPI failed to start, retrying in 10s"
        sleep 10
      fi
    fi

    sleep 10
  done
}

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
echo "🌐 FreeLLMAPI: Check Railway dashboard for domain"
echo "🔑 SSH: Use Railway TCP Proxy"
echo ""

# حلقه اصلی نگهبان برای اطمینان از زنده ماندن Supervisorها
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