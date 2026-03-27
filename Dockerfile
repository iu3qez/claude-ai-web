FROM ghcr.io/linuxserver/baseimage-selkies:debiantrixie

ENV TITLE="Claude Assistant"

# Bun runtime (used to run Claude Code CLI)
COPY --from=oven/bun:latest /usr/local/bin/bun /usr/local/bin/bun

# Add APT repos, install packages, and set up Claude Code CLI in one layer
RUN curl -fsSL https://aaddrick.github.io/claude-desktop-debian/KEY.gpg \
        | gpg --dearmor -o /usr/share/keyrings/claude-desktop.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/claude-desktop.gpg arch=amd64,arm64] \
        https://aaddrick.github.io/claude-desktop-debian stable main" \
        > /etc/apt/sources.list.d/claude-desktop.list && \
    curl -fsSL https://patrickjaja.github.io/claude-cowork-service/install.sh | bash && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        claude-desktop \
        chromium gnome-keyring libsecret-1-0 \
        claude-cowork-service && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /etc/chromium.d && \
    echo 'CHROMIUM_FLAGS="$CHROMIUM_FLAGS --no-sandbox"' > /etc/chromium.d/no-sandbox && \
    sed -i 's|Exec=/usr/bin/claude-desktop %u|Exec=/usr/bin/claude-desktop --no-sandbox %u|' \
        /usr/share/applications/claude-desktop.desktop && \
    BUN_INSTALL=/usr/local bun install -g @anthropic-ai/claude-code && \
    ln -s /usr/local/bin/bun /usr/local/bin/node && \
    rm -rf /root/.bun/install/cache

COPY autostart /defaults/autostart
COPY claude_desktop_config.json /defaults/claude_desktop_config.json

EXPOSE 3000 3001
