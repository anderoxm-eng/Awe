# Dockerfile
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# 1. نصب پکیج‌های پایه و ابزارها
RUN apt-get update && apt-get install -y \
    curl wget git nano vim \
    openssh-server openssh-client \
    build-essential ca-certificates gnupg \
    && rm -rf /var/lib/apt/lists/*

# 2. نصب Node.js نسخه 24 (Active LTS) از NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# 3. نصب سراسری FreeLLMAPI
# بر اساس مستندات پروژه، این پکیج شامل سرور و ابزار CLI است
RUN npm install -g freellmapi@latest

# 4. آماده‌سازی دایرکتوری برنامه و کپی اسکریپت اجرا
RUN mkdir -p /app
WORKDIR /app
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# 5. باز کردن پورت‌ها (پورت 2222 برای SSH و پورت پیش‌فرض Railway)
EXPOSE 8080 2222

CMD ["/app/start.sh"]