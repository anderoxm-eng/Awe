FROM ghcr.io/tashfeenahmed/freellmapi:latest

USER root

RUN apt-get update && \
    apt-get install -y openssh-server && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /run/sshd /etc/ssh && \
    ssh-keygen -A && \
    chmod 700 /etc/ssh && \
    chmod 600 /etc/ssh/ssh_host_*_key && \
    chmod 644 /etc/ssh/ssh_host_*_key.pub

COPY start.sh /app/start.sh

RUN chmod +x /app/start.sh

EXPOSE 3001 2222

CMD ["/app/start.sh"]