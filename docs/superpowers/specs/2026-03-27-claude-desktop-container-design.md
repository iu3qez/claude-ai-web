# Claude Desktop Container — Design Spec
Date: 2026-03-27

## Goal

Run Claude Desktop (with Cowork mode) inside a Docker container, accessible remotely via browser through Selkies WebRTC. The container integrates with external MCP servers for email, Telegram, and WhatsApp, and follows the existing homelab infra patterns (Traefik + Authentik).

---

## Architecture

```
Browser → Traefik (HTTPS, websecure) → Authentik (chain-forwardAuth-authentik@file)
                                              ↓
                                    Container: claude_ai_web
                                    ├── Xvfb (virtual display :1)
                                    ├── Openbox (minimal WM)
                                    ├── Claude Desktop (Electron, autostart)
                                    └── ~/.config/Claude/claude_desktop_config.json
                                              ↓ HTTPS
                                    External MCP servers (via Traefik)
                                    ├── email MCP   (Gmail + Outlook + IMAP)
                                    ├── telegram MCP
                                    └── whatsapp MCP
```

**No volumes** — all data lives inside the container. Reconfiguration on container rebuild is a one-time manual step.

**Network** — `traefik` only. No `db` network needed.

**Domain** — `claude-ai.fabris.me`

---

## Components

### Base Image
`lscr.io/linuxserver/docker-baseimage-selkies`

Provides:
- Xvfb (virtual framebuffer)
- Selkies-GStreamer (WebRTC remote desktop, port 8080)
- linuxserver s6-overlay init system
- User/group mapping via PUID/PGID

### Window Manager
**Openbox** — minimal, lightweight. Configured via `~/.config/openbox/autostart` to launch Claude Desktop on desktop start.

### Claude Desktop
Installed from the `aaddrick/claude-desktop-debian` APT repository:
```
https://aaddrick.github.io/claude-desktop-debian
```

**Cowork backend:** `host` — bubblewrap sandboxing disabled. Rationale: the Docker container itself provides isolation; nested bubblewrap would require `SYS_ADMIN` capabilities without meaningful security benefit.

**Authentication:** OAuth via Claude Max subscription. Login flow happens inside the Electron app (embedded Chromium) on first start. No API key needed.

### MCP Configuration
File: `~/.config/Claude/claude_desktop_config.json` (baked into image or created on first run)

```json
{
  "mcpServers": {
    "email": {
      "url": "https://<email-mcp>.fabris.me/mcp"
    },
    "telegram": {
      "url": "https://<telegram-mcp>.fabris.me/mcp"
    },
    "whatsapp": {
      "url": "https://<whatsapp-mcp>.fabris.me/mcp"
    }
  }
}
```

URLs to be filled with actual endpoints at deploy time.

---

## compose.yaml

Location: `/home/sf/src/claude_ai_web/compose.yaml`

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
      - WIDTH=1920
      - HEIGHT=1080
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.claude-ai-web-rtr.rule=Host(`claude-ai.${DOMAINNAME}`)"
      - "traefik.http.routers.claude-ai-web-rtr.entrypoints=websecure"
      - "traefik.http.routers.claude-ai-web-rtr.middlewares=chain-forwardAuth-authentik@file"
      - "traefik.http.routers.claude-ai-web-rtr.service=claude-ai-web-svc"
      - "traefik.http.services.claude-ai-web-svc.loadbalancer.server.port=8080"
      - "traefik.http.services.claude-ai-web-svc.loadbalancer.server.scheme=http"
```

---

## Dockerfile

Location: `/home/sf/src/claude_ai_web/Dockerfile`

Steps:
1. `FROM lscr.io/linuxserver/docker-baseimage-selkies:latest`
2. Install Openbox + xterm (xterm as emergency terminal)
3. Add claude-desktop-debian APT repo and GPG key
4. Install `claude-desktop`
5. Write Openbox autostart to launch `claude-desktop` on desktop start
6. Set Cowork backend to `host` via env/config

---

## Selkies Display Settings

| Variable | Value |
|----------|-------|
| `WIDTH`  | `1920` |
| `HEIGHT` | `1080` |
| `TITLE`  | `Claude Assistant` |

Selkies serves on port `8080` (internal). Traefik terminates TLS externally.

---

## Authentik Setup (manual, one-time)

1. Create a **Proxy Provider** (Forward auth, single application) in Authentik
   - External host: `https://claude-ai.fabris.me`
2. Create an **Application** and assign the provider
3. The `chain-forwardAuth-authentik@file` middleware in Traefik handles the rest

---

## Out of Scope

- Building the MCP servers for email/Telegram/WhatsApp (separate projects, consumed via HTTP)
- Claude Desktop Cowork rules/automation setup (configured interactively after deploy)
- Volume persistence (intentionally omitted; reconfigure manually on rebuild)
