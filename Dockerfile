FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV NVM_DIR=/root/.nvm
ENV NVM_VERSION=v0.39.7

# Install base dependencies + python3 and make for native addon compilation
RUN apt update && apt install -y \
    curl wget git nano vim \
    openssh-server openssh-client \
    build-essential ca-certificates \
    python3 make g++ \
  && apt clean && rm -rf /var/lib/apt/lists/*

# Install nvm → Node LTS → latest npm
RUN curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash \
  && . "$NVM_DIR/nvm.sh" \
  && nvm install --lts \
  && nvm use --lts \
  && npm install -g npm@latest \
  && npm config set registry https://registry.npmjs.org/

# Make node/npm available system-wide
RUN . "$NVM_DIR/nvm.sh" \
  && NODE_PATH=$(nvm which current) \
  && ln -sf "$NODE_PATH" /usr/local/bin/node \
  && ln -sf "$(dirname $NODE_PATH)/npm" /usr/local/bin/npm \
  && ln -sf "$(dirname $NODE_PATH)/npx" /usr/local/bin/npx

RUN mkdir -p /app
WORKDIR /app

# Clone and build freellmapi
# 1. Delete lockfile: it has 40+ hardcoded npmmirror.com URLs (Railway blocks them)
# 2. Install without lockfile from official registry
# 3. Rebuild better-sqlite3 native addon for the exact Node version in this image
# 4. Build server and client TypeScript
RUN . "$NVM_DIR/nvm.sh" \
  && git clone https://github.com/tashfeenahmed/freellmapi.git /app/freellmapi \
  && cd /app/freellmapi \
  && rm -f package-lock.json desktop/package-lock.json \
  && npm cache clean --force \
  && npm install --no-package-lock \
  && npm rebuild better-sqlite3 --build-from-source \
  && npm run build -w server \
  && npm run build -w client

COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

EXPOSE 8080 2222

CMD ["/app/start.sh"]
