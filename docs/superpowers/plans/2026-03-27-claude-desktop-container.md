# Claude Desktop Container — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Docker image that runs Claude Desktop (Cowork mode) inside a Selkies WebRTC remote desktop, exposed via Traefik + Authentik at `claude-ai.fabris.me`.

**Architecture:** Single container based on `ghcr.io/linuxserver/baseimage-selkies:debiantrixie`. Openbox (already included in base) starts Claude Desktop via autostart script. MCP config is seeded at first run from a template baked into the image.

**Tech Stack:** Docker, ghcr.io/linuxserver/baseimage-selkies (Debian Trixie), Openbox, claude-desktop-debian APT package, Traefik, Authentik.

---

## File Structure

| File | Purpose |
|------|---------|
| `Dockerfile` | Build image from baseimage-selkies, install claude-desktop |
| `compose.yaml` | Service definition with Traefik labels, env vars |
| `root/defaults/autostart` | Openbox autostart: seeds MCP config, launches claude-desktop |
| `root/defaults/claude_desktop_config.json` | MCP config template (URLs filled at deploy) |

---

### Task 1: Write `compose.yaml`

**Files:**
- Create: `/home/sf/src/claude_ai_web/compose.yaml`

- [ ] **Step 1: Create the file**

```yaml
name: claude-ai-web

networks:
  traefik:
    external: true
    name: traefik

services:
  claude-ai-web:
    build: .
    container_name: claude-ai-web
    restart: unless-stopped
    networks:
      - traefik
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
      - TITLE=Claude Assistant
      - SELKIES_MANUAL_WIDTH=1920
      - SELKIES_MANUAL_HEIGHT=1080
      - RESTART_APP=true
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.claude-ai-web-rtr.rule=Host(`claude-ai.${DOMAINNAME}`)"
      - "traefik.http.routers.claude-ai-web-rtr.entrypoints=websecure"
      - "traefik.http.routers.claude-ai-web-rtr.middlewares=chain-forwardAuth-authentik@file"
      - "traefik.http.routers.claude-ai-web-rtr.service=claude-ai-web-svc"
      - "traefik.http.services.claude-ai-web-svc.loadbalancer.server.port=3000"
      - "traefik.http.services.claude-ai-web-svc.loadbalancer.server.scheme=http"
```

> **Note:** `RESTART_APP=true` enables the Selkies watchdog — if `claude-desktop` exits (crash or logout), Openbox relaunches the autostart automatically.

- [ ] **Step 2: Verify the file parses correctly**

```bash
docker compose -f /home/sf/src/claude_ai_web/compose.yaml config
```

Expected: valid YAML printed with env vars interpolated from `/home/sf/.env`.

- [ ] **Step 3: Commit**

```bash
cd /home/sf/src/claude_ai_web
git init
git add compose.yaml
git commit -m "feat: add compose.yaml for claude-desktop selkies container"
```

---

### Task 2: Write MCP config template

**Files:**
- Create: `/home/sf/src/claude_ai_web/root/defaults/claude_desktop_config.json`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p /home/sf/src/claude_ai_web/root/defaults
```

- [ ] **Step 2: Create the MCP config template**

```json
{
  "mcpServers": {
    "email": {
      "url": "https://REPLACE_EMAIL_MCP_URL/mcp"
    },
    "telegram": {
      "url": "https://REPLACE_TELEGRAM_MCP_URL/mcp"
    },
    "whatsapp": {
      "url": "https://REPLACE_WHATSAPP_MCP_URL/mcp"
    }
  }
}
```

> **Before deploying:** replace the three `REPLACE_*` placeholders with the actual Traefik-exposed hostnames of your MCP servers.

- [ ] **Step 3: Commit**

```bash
cd /home/sf/src/claude_ai_web
git add root/defaults/claude_desktop_config.json
git commit -m "feat: add MCP config template for claude-desktop"
```

---

### Task 3: Write Openbox autostart script

**Files:**
- Create: `/home/sf/src/claude_ai_web/root/defaults/autostart`

The autostart script runs as user `abc` inside the container. It:
1. Seeds `claude_desktop_config.json` on first run (idempotent)
2. Optionally sets the Cowork backend to `host` (no bubblewrap)
3. Launches `claude-desktop`

- [ ] **Step 1: Create the autostart file**

```bash
#!/bin/bash

# Seed MCP config on first run
mkdir -p "${HOME}/.config/Claude"
if [ ! -f "${HOME}/.config/Claude/claude_desktop_config.json" ]; then
    cp /defaults/claude_desktop_config.json "${HOME}/.config/Claude/claude_desktop_config.json"
fi

# Launch Claude Desktop (Cowork host backend via env var)
CLAUDE_COWORK_BACKEND=host claude-desktop
```

> **Note on `CLAUDE_COWORK_BACKEND=host`:** This env var disables bubblewrap sandboxing in Cowork mode. If the env var name turns out to be different (verify with `claude-desktop --help` after build), update this line. The Docker container itself provides isolation so no bubblewrap is needed.

- [ ] **Step 2: Make it executable**

```bash
chmod +x /home/sf/src/claude_ai_web/root/defaults/autostart
```

- [ ] **Step 3: Commit**

```bash
cd /home/sf/src/claude_ai_web
git add root/defaults/autostart
git commit -m "feat: add openbox autostart to seed MCP config and launch claude-desktop"
```

---

### Task 4: Write `Dockerfile`

**Files:**
- Create: `/home/sf/src/claude_ai_web/Dockerfile`

- [ ] **Step 1: Create the Dockerfile**

```dockerfile
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
```

> **Why `debiantrixie`?** claude-desktop-debian publishes `.deb` packages; Debian Trixie base matches the APT toolchain. Alpine or Arch tags would require `rpm`/`pkg` workarounds.

> **Why no `VOLUME /config`?** The base image declares it, but we don't override it. Data lives in Docker's anonymous volume tied to the container lifecycle — acceptable per the spec (no explicit volume mount needed).

- [ ] **Step 2: Commit**

```bash
cd /home/sf/src/claude_ai_web
git add Dockerfile
git commit -m "feat: add Dockerfile for claude-desktop selkies container"
```

---

### Task 5: Build and smoke-test the image

- [ ] **Step 1: Build the image**

```bash
cd /home/sf/src/claude_ai_web
docker compose build --progress=plain
```

Expected: build completes without errors. The `apt-get install claude-desktop` step is the longest (~100-300MB download).

If it fails on the GPG key step, run:
```bash
docker compose build --no-cache
```
(transient network issue with the APT repo).

- [ ] **Step 2: Start the container**

```bash
docker compose up -d
```

Expected: container starts, no immediate exit.

- [ ] **Step 3: Verify the container is running**

```bash
docker ps | grep claude-ai-web
```

Expected: container shows `Up` status.

- [ ] **Step 4: Check logs for startup errors**

```bash
docker logs claude-ai-web --tail 50
```

Expected: s6 init services complete, Xvfb starts, Openbox starts, claude-desktop starts. No `FATAL` lines.

- [ ] **Step 5: Verify web UI is reachable on local port**

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000
```

Expected: `200` or `302` (Selkies web UI served by nginx).

> If port 3000 is not directly accessible (no `ports:` in compose — by design), use exec to check inside:
> ```bash
> docker exec claude-ai-web curl -s -o /dev/null -w "%{http_code}" http://localhost:3000
> ```

- [ ] **Step 6: Verify autostart seeded the MCP config**

```bash
docker exec claude-ai-web cat /config/.config/Claude/claude_desktop_config.json
```

Expected: contents of the template file you placed in `root/defaults/`.

- [ ] **Step 7: Commit nothing** — this was a test step, no files changed.

---

### Task 6: Fill in MCP URLs and update the running container

- [ ] **Step 1: Edit the MCP config inside the running container**

```bash
docker exec -it claude-ai-web bash -c \
  'nano /config/.config/Claude/claude_desktop_config.json'
```

Replace the three `REPLACE_*` placeholders with the actual hostnames:
```json
{
  "mcpServers": {
    "email": {
      "url": "https://your-email-mcp.fabris.me/mcp"
    },
    "telegram": {
      "url": "https://your-telegram-mcp.fabris.me/mcp"
    },
    "whatsapp": {
      "url": "https://your-whatsapp-mcp.fabris.me/mcp"
    }
  }
}
```

- [ ] **Step 2: Also update the template in the image** (so future rebuilds have the right URLs)

Edit `/home/sf/src/claude_ai_web/root/defaults/claude_desktop_config.json` with the real URLs, then:

```bash
cd /home/sf/src/claude_ai_web
git add root/defaults/claude_desktop_config.json
git commit -m "chore: fill in actual MCP server URLs"
```

- [ ] **Step 3: Restart claude-desktop inside the container to pick up the new config**

```bash
docker exec claude-ai-web pkill claude-desktop
```

`RESTART_APP=true` watchdog will relaunch it automatically within a few seconds.

---

### Task 7: First-run OAuth login via web UI

- [ ] **Step 1: Open the web UI**

Navigate to `https://claude-ai.fabris.me` in your browser.

Authentik will intercept and ask for login (your existing Authentik session may auto-pass). Once through, you see the Selkies desktop.

- [ ] **Step 2: Log in to Claude Desktop**

Inside the Selkies desktop, Claude Desktop should already be open. Click **Sign in** and complete the OAuth flow with your Claude Max account. The flow happens inside the Electron embedded browser — no external browser needed.

- [ ] **Step 3: Verify Cowork mode is active**

Open a project in Claude Desktop and confirm Cowork mode shows the `host` backend (no bubblewrap warning). If `CLAUDE_COWORK_BACKEND=host` was not the correct env var, check:

```bash
claude-desktop --help 2>&1 | grep -i cowork
claude-desktop --help 2>&1 | grep -i backend
```

Adjust the env var name in `root/defaults/autostart` if needed, rebuild, and redeploy:
```bash
docker compose build && docker compose up -d
```

- [ ] **Step 4: Verify MCP servers are connected**

In Claude Desktop, open Settings → MCP Servers. All three servers (email, telegram, whatsapp) should show green/connected status.

If any show as disconnected:
- Confirm the MCP URL is reachable from inside the container: `docker exec claude-ai-web curl -s https://your-mcp.fabris.me/health`
- Check if Authentik is blocking container→Traefik calls (containers on the `traefik` network can reach other services directly)

---

### Task 8: Set up Authentik provider (manual, one-time)

- [ ] **Step 1: Create Proxy Provider in Authentik**

In Authentik admin UI:
- Type: **Proxy Provider** → Forward auth (single application)
- Name: `claude-ai-web`
- External host: `https://claude-ai.fabris.me`

- [ ] **Step 2: Create Application**

- Name: `Claude Assistant`
- Slug: `claude-ai-web`
- Provider: select the one created above

- [ ] **Step 3: Verify access**

Open a private browser window → navigate to `https://claude-ai.fabris.me`. Should redirect to Authentik login, then land on the Selkies desktop after auth.

---

## Known Unknowns

| Item | How to resolve |
|------|---------------|
| Exact env var for Cowork `host` backend | Run `claude-desktop --help` inside the built container (Task 7, Step 3) |
| Whether MCP servers need auth headers (Authentik token) when called from inside the container | Test in Task 7, Step 4; add `headers` to `claude_desktop_config.json` if needed |
