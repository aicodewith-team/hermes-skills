# Workspace Publish — Implementation Plan (Solution A)

Detailed implementation guide for enabling static site publishing in Mergio workspace containers via web_server.py StaticFiles mount + control plane proxy. Derived from a deep code audit on 2026-06-01.

## Architecture

```
Browser → https://hermes-runtime.aicodewith.com/workspaces/{id}/publish/slug.html
  → Control Plane proxy (main.py, new route, NO auth)
    → http://127.0.0.1:{dashboard_port}/publish/slug.html
      → Workspace container web_server.py (FastAPI :9119)
        → StaticFiles mount serves $HERMES_HOME/public/slug.html
```

All three components are existing infrastructure — no new services, no new ports.

## Commits

### Commit 1: web_server.py — StaticFiles Mount

**Repo:** `NousResearch/hermes-agent`
**File:** `hermes_cli/web_server.py`
**Line:** After line 4825 (`mount_spa(app)`)

```python
# Line 4825 — existing
mount_spa(app)

# === INSERT AFTER ===
# Serve static files published by the agent (e.g. via static-site-publishing skill).
app.mount("/publish", StaticFiles(directory=get_hermes_home() / "public", html=True), name="publish")

# Line 4827 — existing (def start_server)
```

**Why after `mount_spa(app)`:** Starlette Mount objects take precedence over route-based handlers. If mounted before SPA routes, `/publish/` would shadow the SPA catch-all for requests that don't match.

**`html=True`:** Tells Starlette to auto-serve `index.html` for directory requests. Equivalent to nginx `try_files $uri $uri.html $uri/index.html`.

**`get_hermes_home()`:** Returns a `Path`. In workspace containers, `HERMES_HOME` env var is set to `/hermes-cloud/workspaces/{id}/agents/{name}/hermes-home` — under the Nomad host volume, persistent across container restarts.

### Commit 2: dashboard_auth/middleware.py — Public Prefix Whitelist

**Repo:** `NousResearch/hermes-agent`
**File:** `hermes_cli/dashboard_auth/middleware.py`
**Line:** Insert into `_GATE_PUBLIC_PREFIXES` tuple at line 33

```python
_GATE_PUBLIC_PREFIXES: tuple[str, ...] = (
    "/auth/login",
    "/auth/callback",
    "/auth/logout",
    "/login",
    "/api/auth/providers",
    "/assets/",
    "/favicon.ico",
    "/ds-assets/",
    "/fonts/",
    "/fonts-terminal/",
    "/publish/",       # ← INSERT: allow public static files without auth
)
```

**When this matters:** Only when `app.state.auth_required is True` — i.e., non-loopback dashboard binds WITHOUT `--insecure`. Current workspace containers use `--insecure` (set in Nomad template), so `auth_required=False` and this commit is a no-op. It is forward-looking for when workspaces migrate to OAuth-gated dashboards.

### Commit 3: Control Plane — Public Proxy Route

**Repo:** `aicodewith-team/hermes_agent_cloud`
**File:** `control-plane/app/main.py`
**Line:** After `dashboard_proxy` (line 572), before `api_proxy` (line 594)

```python
# ── Public static file publishing (no auth) ─────────────────────────
@app.api_route(
    "/workspaces/{workspace_id}/publish/{path:path}",
    methods=["GET", "HEAD", "OPTIONS"],
)
async def publish_proxy(
    workspace_id: str,
    path: str,
    request: Request,
) -> Response:
    """Proxy static files published by the workspace agent.

    No auth required — these are intentionally public pages.
    Forwards to the dashboard port's /publish/ namespace.
    """
    workspace = get_workspace(workspace_id)
    return await proxy_request(
        request,
        int(workspace["dashboard_port"]),
        f"publish/{path}",
    )
```

**Key decisions:**
- **No `_require_dashboard_access` call** — public pages, no workspace session needed.
- **No `rewrite_prefix`** — static HTML doesn't need URL rewriting (unlike dashboard SPA).
- **`proxy_request()`** reuses the existing proxy function that constructs `http://{workspace_host}:{port}/{path}` and filters hop-by-hop headers.

**`workspace_host`:** Configured in `control-plane/app/config.py` via `HERMES_WORKSPACE_HOST` env var (default `127.0.0.1`). Control plane and workspace containers share the same Nomad host, so localhost works.

### Commit 4: Skill — Workspace Environment Detection

**Repo:** `Mergio-AI/skills`
**File:** `devops/static-site-publishing/SKILL.md`

Key additions already present in Part 0 of the skill. After infrastructure commits land, update Part 0 to remove the "current limitation" warning and document the actual publishing flow:

```
1. Write HTML to $HERMES_HOME/public/<slug>.html
2. Verify: curl -sI https://hermes-runtime.aicodewith.com/workspaces/{id}/publish/<slug>.html
3. Notify user with the control-plane proxy URL
4. Skip ALL nginx/SSH operations
```

## Middleware Compatibility Matrix

All four middleware layers were audited for `/publish/` requests:

| Middleware | Order | Behavior | Impact |
|-----------|-------|----------|--------|
| `CORSMiddleware` | 1 | `allow_origin_regex=localhost\|127.0.0.1` | Static GET requests don't trigger CORS preflight. Same-origin access via control plane proxy is safe. |
| `host_header_middleware` | 2 | Validates Host header against bind address | Workspace binds 0.0.0.0 → accepts all hosts. Control plane forwards with host=127.0.0.1:9119 → matches. |
| `_dashboard_auth_gate` | 3 | Blocks unless path in `_GATE_PUBLIC_PREFIXES` or `auth_required=False` | Workspace `--insecure` → `auth_required=False` → pass-through. Commit 2 handles non-insecure mode. |
| `auth_middleware` | 4 | Only gates `/api/*` paths | `/publish/*` not under `/api/` → ignored. |

**All four pass.** No modifications needed beyond Commit 2 for forward compatibility.

## Short-Term Deployment (No Upstream Image Rebuild)

Commit 1+2 change Hermes Agent source. Workspace containers use `ghcr.io/aicodewith-team/hermes-workspace-vnc@sha256:e825425e...（预装 VNC）` Docker image — changes won't take effect until NousResearch merges PR + publishes new image.

**Workaround:** Patch `web_server.py` at container startup via Nomad template. Add to `start-workspace.sh` before the dashboard starts:

```bash
# Patch web_server.py for static file publishing
WEB_SERVER="$(/opt/hermes/.venv/bin/python -c 'import hermes_cli.web_server; print(hermes_cli.web_server.__file__)')"
if ! grep -q '"/publish"' "$WEB_SERVER" 2>/dev/null; then
    sed -i '/^mount_spa(app)/a\
\
app.mount("/publish", StaticFiles(directory=get_hermes_home() / "public", html=True), name="publish")' "$WEB_SERVER"
fi
```

This is temporary — remove once upstream image includes the change.

## File Paths & Persistence

| Item | Path |
|------|------|
| Volume root | `/hermes-cloud/workspaces/{workspace_id}/` |
| Agent home | `.../agents/{agent_name}/hermes-home/` |
| Publish dir | `.../agents/{agent_name}/hermes-home/public/` |
| Agent writes to | `$HERMES_HOME/public/<slug>.html` |
| Served at | `https://hermes-runtime.aicodewith.com/workspaces/{id}/publish/<slug>.html` |

The publish directory is under the Nomad `host` volume — survives container restarts and rescheduling (same node).

**Multi-agent isolation:** Each agent has independent `HERMES_HOME` → independent `public/` directory. Different agents' published files don't conflict.

## Test Strategy

### Unit Test (web_server.py)
In `tests/hermes_cli/test_web_server.py`, add a test:
```python
def test_publish_static_files_served(client):
    """Static files under /publish/ are served without auth."""
    pub_dir = get_hermes_home() / "public"
    pub_dir.mkdir(parents=True, exist_ok=True)
    (pub_dir / "test.html").write_text("<h1>Hello</h1>")
    response = client.get("/publish/test.html")
    assert response.status_code == 200
    assert b"<h1>Hello</h1>" in response.content
```

### Integration Test (control plane)
In `tests/test_workspaces.py`, add:
1. Create workspace → write file to `public/` on container
2. `GET /workspaces/{id}/publish/test.html` → 200 + correct content
3. `GET /workspaces/{id}/publish/../../../etc/passwd` → 404 (path traversal protection from Starlette StaticFiles)

### Smoke Test (manual)
```bash
# 1. Write test file in workspace container
echo "<h1>hello</h1>" > $HERMES_HOME/public/smoke.html

# 2. Access via control plane
curl -s https://hermes-runtime.aicodewith.com/workspaces/{id}/publish/smoke.html
# Expected: HTTP 200 + "<h1>hello</h1>"
```

## URL Comparison: Before vs After

| | Before (broken) | After (fixed) |
|---|---|---|
| Write to | `/opt/data/www/slug.html` (ephemeral) | `$HERMES_HOME/public/slug.html` (persistent) |
| Served by | nginx :80 (not installed) | web_server.py :9119 StaticFiles |
| Public URL | `https://hermes-daqiezi.mergio.dev/slug.html` (wrong host) | `https://hermes-runtime.aicodewith.com/workspaces/{id}/publish/slug.html` |
| Auth | None (nginx) | None (public proxy, no auth) |
| Hot reload | N/A | Instant (StaticFiles reads filesystem directly) |
