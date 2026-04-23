# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Dockerized always-on Claude Desktop accessible from any browser, running inside a WebRTC remote desktop (Selkies). It packages three community projects that together make Claude's Cowork mode work on Linux without a hypervisor:

- `linuxserver/baseimage-selkies` — WebRTC desktop + Openbox + Xvfb
- `claude-desktop-debian` (aaddrick) — unofficial Electron Claude Desktop
- `claude-cowork-service` (patrickjaja) — socket daemon replacing the Cowork VM on Linux

Claude Code CLI is installed globally via Bun (`ln -s bun node` covers packages that shebang `/usr/bin/env node`).

## Common commands

```bash
docker compose build                      # rebuild image
docker compose up -d --force-recreate     # start/restart fresh
docker compose logs -f                    # follow container logs
docker compose restart                    # restart without recreating
docker exec claude-ai-web tail -f /config/cowork-svc.log   # cowork daemon log
docker exec claude-ai-web tail -f /config/.config/Claude/logs/main.log   # Electron main process log
```

## Architecture notes

### Autostart / watchdog interaction (fragile — read before editing `autostart`)

The base image's s6 watchdog (`RESTART_APP=true`) monitors a process matching `sh $HOME/.config/openbox/autostart` and restarts it whenever that PID disappears. Three things must all hold for the system to be stable:

1. **Don't `exec` inside `autostart`.** `exec` replaces the `sh autostart` process, making the watchdog lose it and relaunch a second one. Keep the final command in foreground without `exec`.
2. **Detach `cowork-svc-linux` with `setsid`.** When `sh autostart` exits, s6 kills its process group; a plain `&` spawn gets SIGTERM'd. `setsid --fork` moves it into a new session that survives.
3. **Don't spawn a second `claude-desktop` if one is already running.** Electron's singleton lock makes the duplicate exit immediately → `sh autostart` exits → watchdog restarts → duplicate exits... infinite loop. The `pgrep -f "electron.*app\.asar"` check gates this; the fallback is `sleep infinity` so the watchdog keeps seeing a live `sh autostart`.

### `pgrep` gotcha

The binary is `cowork-svc-linux` (16 chars). `pgrep -x cowork-svc-linux` silently matches nothing — the kernel comm name is capped at 15 chars. Always use `pgrep -xf /usr/bin/cowork-svc-linux` for this daemon.

### Stale Singleton locks

Electron creates `SingletonLock`/`SingletonSocket`/`SingletonCookie` in `~/.config/Claude/`. An unclean container stop leaves these behind and every subsequent launch returns "Not main instance". `autostart` removes them on fresh starts (i.e., only when no Electron is already running).

### Autostart file lives in three places

The base image copies `/defaults/autostart` to **two** runtime locations on first run — and only if they don't exist:
- `/config/autostart` (unused for execution here; leftover)
- `/config/.config/openbox/autostart` ← **this is what Openbox actually runs**

Rebuilding the image does **not** refresh `/config/.config/openbox/autostart` on existing volumes. After a Dockerfile change that affects `autostart`, either `rm` that file (the base image will recopy) or `docker cp autostart claude-ai-web:/config/.config/openbox/autostart`.

### Container quirks

- `security_opt: seccomp:unconfined` in `compose.yaml` is required for Cowork (some syscalls the daemon uses are blocked by Docker's default seccomp profile).
- Chromium needs `--no-sandbox` in Docker; set via `/etc/chromium.d/no-sandbox` in the Dockerfile.
- Claude Desktop also needs `--no-sandbox --disable-gpu --disable-gpu-compositing --disable-dev-shm-usage` to avoid Electron zygote crashes.
- WebSockets to `/websocket` must bypass Authentik — WebSocket handshakes can't follow OAuth redirects. The compose file defines a second Traefik router at priority 20 for this.

### APT repo URL

`claude-desktop-debian` moved from `aaddrick.github.io/claude-desktop-debian` to `pkg.claude-desktop-debian.dev` (GitHub Pages returns a 301; APT does not follow redirects). The Dockerfile already uses the new URL.

## MCP server configuration

`claude_desktop_config.json` is shipped empty on purpose — MCP servers are configured interactively via Claude Desktop's UI after login. The file exists so the app doesn't error on first launch.

## Environment

Requires `.env` (or symlink to `/home/sf/.env`) with: `PUID`, `PGID`, `TZ`, `DOMAINNAME`. Traefik network `traefik` and Authentik middleware `chain-forwardAuth-authentik@file` must be externally available.
