FROM ghcr.io/linuxserver/baseimage-selkies:debiantrixie

ENV TITLE="Claude Assistant"

# Install claude-desktop from aaddrick/claude-desktop-debian APT repo
RUN curl -fsSL https://aaddrick.github.io/claude-desktop-debian/KEY.gpg \
        | gpg --dearmor -o /usr/share/keyrings/claude-desktop.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/claude-desktop.gpg arch=amd64,arm64] \
        https://aaddrick.github.io/claude-desktop-debian stable main" \
        > /etc/apt/sources.list.d/claude-desktop.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends claude-desktop && \
    rm -rf /var/lib/apt/lists/*

# Copy defaults (autostart + MCP config template)
COPY root/ /

EXPOSE 3000 3001
