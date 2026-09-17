FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && apt install -y \
    curl wget git nano vim \
    openssh-server openssh-client \
    build-essential nodejs npm

RUN mkdir -p /app
WORKDIR /app

COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

EXPOSE 8080 2222

CMD ["/app/start.sh"]
