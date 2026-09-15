FROM docker.io/debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install systemd and verification dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    systemd systemd-sysv \
    curl jq openssl uuid-runtime qrencode iproute2 iptables python3 \
    openssh-server \
    tor \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Enable systemd as PID 1
STOPSIGNAL SIGRTMIN+3
CMD ["/lib/systemd/systemd"]
