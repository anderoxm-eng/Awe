FROM ghcr.io/tashfeenahmed/freellmapi:latest

USER root

# Install SSH, generate host keys, and make /etc/ssh fully writable by root at build time
RUN apt-get update && apt-get install -y openssh-server \
  && apt-get clean && rm -rf /var/lib/apt/lists/* \
  && mkdir -p /run/sshd /etc/ssh \
  && ssh-keygen -A \
  && chmod 700 /etc/ssh \
  && chmod 600 /etc/ssh/ssh_host_*_key \
  && chmod 644 /etc/ssh/ssh_host_*_key.pub \
  # Make shadow writable so start.sh can set root password at runtime
  && chmod 666 /etc/shadow \
  # Make sshd_config dir writable so start.sh can write config
  && chmod 777 /etc/ssh

COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

EXPOSE 3001 2222

CMD ["/app/start.sh"]
