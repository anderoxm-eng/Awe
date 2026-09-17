FROM ghcr.io/tashfeenahmed/freellmapi:latest

# PORT is set by Railway automatically.
# ENCRYPTION_KEY must be set as a Railway Variable (hex 64 chars).
# If not set, a random one is generated each deploy — keys won't persist.
ENV PORT=3001

EXPOSE 3001
