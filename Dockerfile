FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install Node.js 20 (freellmapi requires Node 20+), plus SSH and tools
RUN apt update && apt install -y \
    curl wget git nano vim \
    openssh-server openssh-client \
    build-essential ca-certificates gnupg \
  && mkdir -p /etc/apt/keyrings \
  && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
     | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
  && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
     > /etc/apt/sources.list.d/nodesource.list \
  && apt update && apt install -y nodejs \
  && apt clean && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /app
WORKDIR /app

# Clone freellmapi and install dependencies at build time
RUN git clone https://github.com/tashfeenahmed/freellmapi.git /app/freellmapi \
  && cd /app/freellmapi \
  && npm install

COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# freellmapi dashboard + SSH
EXPOSE 8080 2222

CMD ["/app/start.sh"]
