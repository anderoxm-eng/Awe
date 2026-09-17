FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV NVM_DIR=/root/.nvm
ENV NVM_VERSION=v0.39.7

# Install base dependencies
RUN apt update && apt install -y \
    curl wget git nano vim \
    openssh-server openssh-client \
    build-essential ca-certificates \
  && apt clean && rm -rf /var/lib/apt/lists/*

# Install nvm → Node LTS → latest npm
RUN curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash \
  && . "$NVM_DIR/nvm.sh" \
  && nvm install --lts \
  && nvm use --lts \
  && npm install -g npm@latest

# Make node/npm available system-wide without sourcing nvm each time
RUN . "$NVM_DIR/nvm.sh" \
  && NODE_PATH=$(nvm which current) \
  && ln -sf "$NODE_PATH" /usr/local/bin/node \
  && ln -sf "$(dirname $NODE_PATH)/npm" /usr/local/bin/npm \
  && ln -sf "$(dirname $NODE_PATH)/npx" /usr/local/bin/npx

RUN mkdir -p /app
WORKDIR /app

# Clone freellmapi, force clean install from official registry, then build
RUN . "$NVM_DIR/nvm.sh" \
  && git clone https://github.com/tashfeenahmed/freellmapi.git /app/freellmapi \
  && cd /app/freellmapi \
  # package-lock.json may contain npmmirror.com URLs which Railway blocks;
  # delete it so npm regenerates a clean lockfile from the official registry.
  && rm -f package-lock.json \
  && npm config set registry https://registry.npmjs.org/ \
  && npm install \
  && npm run build -w server \
  && npm run build -w client

COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# freellmapi dashboard + SSH
EXPOSE 8080 2222

CMD ["/app/start.sh"]
