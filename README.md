# claude-ai-web

A Dockerized **always-on Claude Desktop** accessible from any browser via WebRTC remote desktop, powered by [Selkies](https://github.com/selkies-project/selkies) and [linuxserver.io](https://www.linuxserver.io/) base images.

Runs Claude Desktop in **Cowork mode** — Claude's agentic workspace — with full MCP server support for connecting external tools (email, messaging, calendars, etc.).

## How it works

- **[linuxserver/baseimage-selkies](https://github.com/linuxserver/docker-baseimage-selkies)** provides a full Linux desktop (Openbox + Xvfb) streamed to the browser via WebRTC, accessible on port 3000.
- **[claude-desktop-debian](https://github.com/aaddrick/claude-desktop-debian)** — unofficial Electron-based Claude Desktop for Linux — runs inside the desktop session.
- **[claude-cowork-service](https://github.com/patrickjaja/claude-cowork-service)** — community daemon that implements the Cowork VM socket protocol, enabling Cowork mode on Linux without a hypervisor.
- **Traefik** handles HTTPS reverse proxying. Authentik provides SSO authentication.

## Features

- Full Claude Desktop UI in the browser — no local installation needed
- Cowork (agentic workspace) fully functional on Linux
- MCP servers configured directly via Claude Desktop's UI
- OAuth login preserved across restarts via gnome-keyring
- WebSocket traffic bypasses auth middleware for uninterrupted streaming
- Persistent config under `/config/` (Claude settings, MCP config, Cowork state)

## Requirements

- Docker with Compose
- Traefik reverse proxy on a `traefik` Docker network
- (Optional) Authentik for SSO authentication
- A domain name

## Usage

1. Clone the repo:
   ```bash
   git clone https://github.com/iu3qez/claude-ai-web
   cd claude-ai-web
   ```

2. Create a `.env` file (or symlink your global one):
   ```env
   PUID=1000
   PGID=1000
   TZ=Europe/Rome
   DOMAINNAME=example.com
   ```

3. Build and start:
   ```bash
   docker compose build
   docker compose up -d
   ```

4. Open `https://claude-ai.example.com` in your browser.

5. On first launch, Claude Desktop will prompt for OAuth login. Use the Chromium browser that opens inside the desktop session.

6. Configure MCP servers via **Claude Desktop → Settings → MCP**.

## Architecture

```
Browser → Traefik (HTTPS) → Authentik (SSO) → Selkies WebRTC → Openbox desktop
                                                                      └─ cowork-svc-linux (socket daemon)
                                                                      └─ claude-desktop (Electron)
                                                                            └─ claude (Claude Code CLI, via Bun)
```

The WebSocket path (`/websocket`) uses a separate Traefik router without Authentik middleware — WebSockets cannot follow OAuth redirects.

## Traefik labels

The compose file defines two routers:
- **Main router** (`claude-ai-web-rtr`): all traffic through Authentik forward auth
- **WebSocket router** (`claude-ai-web-ws-rtr`): `/websocket` path, priority 20, no auth

## Persistent data

Everything under `/config/` persists across restarts:
- `~/.config/Claude/` — Claude Desktop settings and MCP configuration
- `~/.config/Claude/claude_desktop_config.json` — seeded from `claude_desktop_config.json` on first run
- Cowork workspace state

## Credits

- [linuxserver/docker-baseimage-selkies](https://github.com/linuxserver/docker-baseimage-selkies) — GPL-3.0
- [aaddrick/claude-desktop-debian](https://github.com/aaddrick/claude-desktop-debian) — Apache-2.0
- [patrickjaja/claude-cowork-service](https://github.com/patrickjaja/claude-cowork-service) — MIT
- [oven-sh/bun](https://github.com/oven-sh/bun) — MIT

## License

MIT — see [LICENSE](LICENSE).
