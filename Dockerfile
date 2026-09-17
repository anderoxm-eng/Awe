FROM ghcr.io/tashfeenahmed/freellmapi:latest

# فقط برای SSH و supervisor
USER root
RUN apt-get update && apt-get install -y openssh-server curl && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /run/sshd

COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

EXPOSE 3001 2222
CMD ["/app/start.sh"]