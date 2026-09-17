# Use the official pre-built FreeLLMAPI image — no build step, no native addon issues
FROM ghcr.io/tashfeenahmed/freellmapi:latest

# Install SSH server on top of the existing image
USER root
RUN apt-get update && apt-get install -y \
    openssh-server \
  && apt-get clean && rm -rf /var/lib/apt/lists/* \
  && mkdir -p /run/sshd

COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# FreeLLMAPI default port + SSH
EXPOSE 3001 2222

CMD ["/app/start.sh"]
