#!/bin/bash

# ⚠️ عمداً set -e نداریم
OPENCODE_PORT=${PORT:-3001}
SSH_PORT=2222

SSH_USERNAME=${SSH_USERNAME:-root}
SSH_PASSWORD=${SSH_PASSWORD:-}

echo "========================================"
echo "  Railway FreeLLMAPI + SSH"
echo "========================================"

# ---------- SSH Setup ----------
echo "🔐 Configuring SSH..."
mkdir -p /run/sshd
cat > /etc/ssh/sshd_config << SSHEOF
Port $SSH_PORT
PermitRootLogin yes
PasswordAuthentication yes
PermitEmptyPasswords no
UsePAM no
Subsystem sftp /usr/lib/openssh/sftp-server
SSHEOF

ssh-keygen -A

if [ -n "$SSH_PASSWORD" ]; then
  echo "root:$SSH_PASSWORD" | chpasswd
else
  SSH_PASSWORD="changeme123"
  echo "root:$SSH_PASSWORD" | chpasswd
  echo "⚠️  SSH_PASSWORD not set — using fallback: $SSH_PASSWORD"
fi

# ---------- Supervisor for SSH ----------
supervise_sshd() {
  while true; do
    if ! pgrep -f "/usr/sbin/sshd -D" >/dev/null 2>&1; then
      /usr/sbin/sshd -D -f /etc/ssh/sshd_config &
      sleep 2
    fi
    sleep 5
  done
}

# ---------- Supervisor for FreeLLMAPI ----------
# ایمیج رسمی خودش سرور را اجرا می‌کند، ما فقط چک می‌کنیم که زنده است
supervise_freellmapi() {
  while true; do
    if ! curl -s -o /dev/null -m 5 -w "%{http_code}" "http://127.0.0.1:3001/api/ping" | grep -qE "^[23]"; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] FreeLLMAPI not responding"
    fi
    sleep 15
  done
}

echo "🚀 Starting supervisors..."
supervise_sshd &
supervise_freellmapi &

echo "========================================"
echo "  Services Ready"
echo "========================================"

# حلقه اصلی
while true; do
  sleep 10
done