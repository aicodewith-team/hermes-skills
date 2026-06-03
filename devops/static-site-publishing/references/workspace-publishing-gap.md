# Workspace Static Site Publishing Gap

## Why this exists

The `static-site-publishing` skill was designed for the daqiezi-hermes instance
running on 38.190.178.92 in a Dokploy-managed Docker Swarm with nginx + Traefik.
Mergio workspace containers (Nomad-managed, based on `ghcr.io/aicodewith-team/hermes-workspace-vnc（预装 VNC）`)
have none of that infrastructure, so the skill fails end-to-end.

## Environment Comparison

| | daqiezi-hermes | Workspace Container |
|---|---|---|
| Orchestrator | Dokploy / Docker Swarm | Nomad |
| Host | 38.190.178.92 | Nomad node (different host) |
| Base image | Custom (has nginx) | `ghcr.io/aicodewith-team/hermes-workspace-vnc（预装 VNC）` |
| Web server | nginx on :80 | ❌ None |
| Static root | `/opt/data/www/` nginx serve | `/opt/data/www/` empty, not served |
| File persistence | Host volume | Only under `/hermes-cloud/workspaces/{id}/` |
| DNS | `hermes-daqiezi.mergio.dev` | None |
| Traefik routing | Static file route → daqiezi-hermes:80 | Dashboard proxy only |
| Exposed ports | :80 (nginx) | :9119 (dashboard), :8642 (api) |
| SSH access | `ssh root@38.190.178.92` | Not available |

## Nomad Template Evidence

From `aicodewith-team/hermes_agent_cloud` at `deploy/nomad/hermes-workspace.nomad.tpl`:

### Non-VNC workspace
```
network {
  port "dashboard" {
    static = {{ dashboard_port }}
    to     = 9119        # Dashboard directly, no nginx in front
  }
}
```
No port 80, no nginx, no static file serving.

### VNC workspace (has nginx, but proxied)
```nginx
server {
    listen 80;
    root /opt/data/www;       # Set but unused
    index index.html;

    location / {
        proxy_pass http://127.0.0.1:9119;  # All requests → dashboard
    }
}
```
Even VNC workspaces don't serve static files — `root` is overridden by `proxy_pass`.

## Full Failure Chain (from user report, 2026-06-01)

1. User creates Hermes workspace in Mergio Dashboard → Nomad provisions container
2. Skill `static-site-publishing` installed to workspace → Agent reads instructions
3. Agent writes HTML to `/opt/data/www/dali-travel-guide.html` ✅
4. Agent browses the local file → validates content, theme, zero errors ✅
5. Agent tries `curl https://hermes-daqiezi.mergio.dev/dali-travel-guide.html` → ❌
   - Either connection refused (no nginx on :80 in this container)
   - Or 404 (DNS points to daqiezi-hermes, not this workspace)
6. Agent tries `ssh root@38.190.178.92 "docker exec daqiezi-hermes ..."` → ❌
   - No route to host (different machine)
   - No SSH key in workspace container
7. Agent concludes "nginx 当前环境未安装，无法部署到公网"

## What the Workspace DOES Have

- **Hermes Dashboard** on :9119 — `web_server.py` (FastAPI) serving React SPA + REST API
  - Already imports `from fastapi.staticfiles import StaticFiles`
  - One-line fix: `app.mount("/publish", StaticFiles(directory=get_hermes_home() / "public"))`
- **Volume** at `/hermes-cloud/workspaces/{id}/` — host volume, persists across container restarts
  - `$HERMES_HOME` is under this volume → `$HERMES_HOME/public/` would be persistent
- **Control Plane Proxy** at `https://hermes-runtime.aicodewith.com`
  - Existing: `/workspaces/{id}/dashboard/*` → container:9119
  - Existing: `/workspaces/{id}/api/*` → container:8642
  - Needed: `/workspaces/{id}/publish/*` → container:9119/publish/*

## Fix Dependencies (ordered)

| Repo | Change | Lines |
|------|--------|-------|
| `NousResearch/hermes-agent` | `web_server.py`: mount StaticFiles at `/publish` | 1 |
| `aicodewith-team/hermes_agent_cloud` | `main.py`: add `/workspaces/{id}/publish/*` proxy route | ~15 |
| `Mergio-AI/skills` | Skill: detect `WORKSPACE_ID`, use workspace publishing flow | ~50 |

Full implementation detail (exact line numbers, middleware audit, test strategy): see `workspace-publish-implementation.md` in this skill's references.
| `aicodewith-team/hermes_agent_cloud` | Nomad template: optional `ln -sf` for `/opt/data/www` → volume | 3 |

## Key Insight

"nginx 未安装" isn't the root cause. Even if nginx were installed, `hermes-daqiezi.mergio.dev`
points to a different machine, Traefik routes to a different container, and the file system
isn't persistent. Every instruction in the current skill is hardcoded to one specific instance.

The fix requires three layers:
1. **Serve ability** — web_server.py StaticFiles mount
2. **Route** — control plane proxy to expose it publicly
3. **Skill awareness** — detect workspace mode and use the correct publishing flow
