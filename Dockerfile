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

# Install nvm → Node LTS → latest npm (same method that works locally)
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

# Clone freellmapi, install dependencies, and build at image build time
RUN . "$NVM_DIR/nvm.sh" \
  && git clone https://github.com/tashfeenahmed/freellmapi.git /app/freellmapi \
  && cd /app/freellmapi \
  && npm config set registry https://registry.npmjs.org/ \
  && npm install --prefer-online \
  && npm run build -w server \
  && npm run build -w client

COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# freellmapi dashboard + SSH
EXPOSE 8080 2222

CMD ["/app/start.sh"]
