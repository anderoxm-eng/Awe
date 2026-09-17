FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# نصب پیش‌نیازها (Git برای کلون، curl برای نصب Node)
RUN apt-get update && apt-get install -y \
    curl wget git nano vim \
    openssh-server openssh-client \
    build-essential ca-certificates gnupg \
    && rm -rf /var/lib/apt/lists/*

# نصب Node.js 20 (مورد نیاز FreeLLMAPI)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# آماده‌سازی دایرکتوری برنامه
RUN mkdir -p /app
WORKDIR /app

# کپی اسکریپت supervisor
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# باز کردن پورت‌ها: 8080 (Railway) و 2222 (SSH)
EXPOSE 8080 2222

CMD ["/app/start.sh"]