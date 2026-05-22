---
name: static-site-publishing
description: >-
  Publish static HTML pages to the public web. Part 1: setup infrastructure
  (unified HTTP server, reverse proxy, watchdog). Part 2: author and deploy
  pages (CSS patterns, mobile layouts, Chinese doc conventions). Use when
  building a static site or publishing HTML pages.
---

# Static Site Publishing

Publish HTML pages by dropping files in a directory — zero deploy steps.

## Part 1: 搭建基础设施

### Architecture

```
用户 → DNS → Reverse Proxy (Traefik/Nginx/Caddy) → serve.py :8080
                                                      │
                                                      ├── 匹配静态文件 → 直接返回
                                                      └── 不匹配       → 代理到 API Gateway
```

`s serve.py` is the single entry point for the domain. The reverse proxy has one router rule — no competing configs. The server handles internal routing.

### serve.py — Unified HTTP Server

Copy `scripts/serve.py` from this skill. Configuration at the top of the file:

```python
PORT = 8080                    # listen port
ROOT = "/path/to/static/files" # where .html files live
API_BACKEND = "http://127.0.0.1:8642"  # fallback proxy (optional, set to None to disable)
```

**Clean URL mapping:**

| Request | Tries in order |
|---------|---------------|
| `/foo` | `/foo.html` → `/foo/index.html` → proxy to API |
| `/` | `/index.html` → directory listing |

**Key features:**
- All HTTP methods (GET/POST/PUT/DELETE/PATCH) — non-GET requests proxy through
- `X-Forwarded-For` / `X-Forwarded-Host` headers on proxied requests
- HTML directory listing with clickable links
- 502 on backend unreachable

Start: `python3 serve.py` — runs in foreground. Use process supervision (below) to keep it alive.

### Process Supervision

Use any process supervisor (systemd, supervisor, or cron watchdog). The watchdog script (`scripts/serve-watchdog.sh`) is a minimal cron-based approach:

```bash
# Cron: every 1 minute, silent when healthy
# Prints message only when restart was needed
*/1 * * * * /path/to/serve-watchdog.sh
```

The watchdog exits 0 with no output when `serve.py` is alive. Only prints on restart.

### Reverse Proxy Setup

Generic pattern — adapt to your proxy:

**Traefik (Docker label):**
```yaml
labels:
  - "traefik.http.routers.static.rule=Host(`your-domain.com`)"
  - "traefik.http.services.static.loadbalancer.server.port=8080"
```

**Nginx:**
```nginx
server {
    server_name your-domain.com;
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
    }
}
```

**Caddy:**
```
your-domain.com {
    reverse_proxy 127.0.0.1:8080
}
```

### Adding a New Domain

1. Point DNS to your server IP
2. Add the domain to your reverse proxy config (router rule / server block)
3. Done — `serve.py` handles all paths

### Shared Theme CSS

Put `templates/light-theme.css` in your static root as `theme.css`. All pages reference it:

```html
<link rel="stylesheet" href="/theme.css">
```

CSS variables for consistent colors:

| Variable | Default | Usage |
|----------|---------|-------|
| `--bg` | `#ffffff` | Page background |
| `--surface` | `#f8f9fa` | Card / section bg |
| `--surface2` | `#e9ecef` | Table header / secondary |
| `--border` | `#dee2e6` | Borders |
| `--text` | `#212529` | Body text |
| `--text2` | `#6c757d` | Secondary text |
| `--accent` | `#7c3aed` | Primary accent |
| `--red` | `#dc3545` | Critical / danger |
| `--green` | `#198754` | Success |
| `--amber` | `#e6a817` | Warning |
| `--blue` | `#0d6efd` | Info / neutral |

Includes base styles: header, sections, cards, tables, highlight boxes, timelines, score bars, principle grids, and footer. Each page only needs a minimal `<style>` block for page-specific components.

---

## Part 2: 使用基础设施

### Security: Sanitize Before Publishing

**ALWAYS run this check before dropping a file into `$ROOT`:**

```bash
grep -nE "(sk-|whsec_|api_key|password|token|secret|key_value|http://127\.|http://10\.|http://192\.168\.|DATABASE_URL=)" /path/to/file.html
```

If any line matches, **strip or mask it** before publishing. Never expose:
- Internal IPs (`127.0.0.1`, `10.x`, `192.168.x`) — replace with `...` or the public URL
- API keys / secrets — replace with `...`
- Provider names / model IDs that reveal infrastructure choices — replace with `...`
- Database connection strings — replace with `...`

**Env var sections in docs are especially dangerous.** When converting markdown to HTML, always replace sensitive values:

```bash
# Safe: env var names only
DATABASE_URL=...
STRIPE_SECRET_KEY=...
AICODEWITH_API_BASE=...

# Dangerous: actual values exposed
DATABASE_URL=postgresql://user:pass@host/db
AICODEWITH_API_BASE=https://api.aicodewith.com
```

### Quick Workflow

1. Write HTML page
2. **Run sanitization check** (above)
3. Drop it in the static files directory (default: `$ROOT`)
4. Page is live instantly at `https://your-domain.com/<slug>`

Link the shared theme, then add page-specific styles.

### Content Structure: Pages Are Presentations, Not Dumps

HTML pages published to the web are for **human readers**, not machines. Think of them as a presentation slide deck or a briefing document — not a technical spec dump.

**Every page must have:**

| Section | Purpose | Example |
|---|---|---|
| **Hero** | One sentence that says what this is | "Your AI agent, hosted on Telegram. Zero setup." |
| **Why** | Why does this exist? Why should the reader care? | Pain point → solution narrative |
| **How It Works** | Step-by-step flow, visual if possible | 3 steps with arrows or numbered cards |
| **Comparison / Differentiator** | How is this different from alternatives? | Table or side-by-side cards |
| **Pricing / Details** | What's the cost, what do they get? | Card grid or table |
| **FAQ** | Answer the obvious questions | 5-6 Q&A pairs |

**Anti-pattern: raw Markdown → HTML conversion.** Never take a `PLAN.md` or `README.md` and convert it directly to HTML. It reads like internal notes, not a product page. Write narrative HTML from scratch.

**Anti-pattern: too terse.** A page with just one hero section and nothing else is not a presentation. The reader needs context — why, how, compared to what, how much.

**When converting from internal docs to public pages:**
1. Strip all internal details (env vars with values, internal URLs, model names, database connection strings)
2. Rewrite technical schemas as visual diagrams or flow descriptions
3. Add narrative context between sections — don't just list facts
4. Run the sanitization grep before publishing

### Must-Have CSS Fixes

**Code blocks: always add `white-space: pre-wrap`**

`<div>` collapses whitespace by default. All code display elements need:

```css
.code-block, .dir-tree {
  white-space: pre-wrap;   /* preserve newlines and indentation */
  word-break: break-word;  /* wrap long lines */
}
```

**Mobile branching: flex-direction toggle**

Side-by-side layouts must stack vertically on narrow screens:

```css
@media (max-width: 640px) {
  .branch-container { flex-direction: column !important; }
}
```

### Page Structure Patterns

| Pattern | CSS class | Use case |
|---------|-----------|----------|
| Flow steps | `.flow-steps` > `.flow-step` + `.flow-arrow` | Pipeline / process |
| Branching | `.branch-container` with `display:flex` children | A/B comparison |
| Data tables | `.compare-table` / `.insight-table` | Structured comparisons |
| Highlight boxes | `.highlight-box` + color variant | Key takeaways |

### Navigation

Always add footer pagination between related pages:

```html
<footer>
  <p>← <a href="/page-1">上一页</a> | <a href="/page-3">下一页 →</a></p>
</footer>
```

### Chinese Internal Doc Conventions

When writing employee-facing internal documents:

**Perspective: "你", not "客服/员工"** — the document speaks to the reader.

| Boss voice (avoid) | Employee voice (use) |
|---|---|
| 淘汰 | 不再继续合作 |
| 筛选 | 冲刺 / 成长为 |
| 老板介入 | 升级求助 |
| 管理原则 | 我们的理念 |
| 差客服 / 老板永远在兜底 | 需要提升 / 需要他人兜底 |

- **Footer tag**: use `员工手册` for employee docs
- **Badge**: use `V1.0 · 员工手册`, not `V1.0 · 老板兜底版`

### Mobile Testing

Always test on mobile before shipping. Pages that look perfect at desktop routinely break on phones — collapsed code blocks, overflowing tables, columns that don't stack.

### Pitfalls

- **DON'T DEBUG THE INFRASTRUCTURE IF IT ALREADY WORKS.** If the domain already serves pages, the reverse proxy, DNS, and serve.py are proven. Do NOT port-scan, check firewall rules, try SSH tunnels, spin up test HTTP servers, or reconfigure Traefik. Just write the HTML and drop it in `$ROOT`. The page goes live in under a second. Checking infrastructure when it works wastes time and frustrates the user. The rule is: if `curl https://your-domain.com/existing-page` returns 200, the infra is fine — write your file and move on.

- **Write a proper HTML page, not a markdown dump.** Never convert a README.md or PLAN.md to HTML verbatim and publish it. Technical docs have no introduction, no narrative flow, no readability — they're spec dumps. Write a real page: hero section that says what this is, sections that explain it in plain language, a comparison table if relevant, FAQ. Use the shared theme.css utility classes (`.card`, `.card-grid`, `.highlight-box`, `.table-wrap`, `.flow-steps`) — they're there to make pages look good with minimal effort.

- **Dokploy/Traefik environments**: Do NOT install Caddy or Nginx when Dokploy already manages Traefik. The `dokploy-network` overlay handles inter-container routing — just add a dynamic config YAML to `/etc/dokploy/traefik/dynamic/` with the appropriate `Host()` rule pointing to your container. Adding a second reverse proxy causes port conflicts on 80/443.

- **Sanitize before publishing**: Always grep for `sk-`, `whsec_`, internal IPs, provider names in env vars, and database connection strings before dropping a file. See "Security: Sanitize Before Publishing" above.

- **Docker overlay networks**: Containers must be on `dokploy-network` (or the Traefik network) for Traefik to reach them. Use `docker network connect`.

- **Server crash → 502**: If `serve.py` dies, watchdog auto-restarts within 1 minute

- **Code blocks garbled**: Missing `white-space: pre-wrap` — browsers collapse whitespace

- **Mobile layout broken**: Side-by-side columns don't stack — add `@media` query

- **Long lines overflow**: Paths/URLs break layout — add `word-break: break-word`

- **Footer links stale**: When adding pages, update nav links on ALL pages in the chain

- **File encoding**: HTML files must be UTF-8

- **Path casing**: URLs are case-sensitive. `/Org-OS` won't match `org-os.html`

- **Feishu Markdown links: never wrap URLs in `**bold**`.** When sharing a published URL in a Feishu/Lark message, write the URL bare — `https://example.com/page` — not `**https://example.com/page**`. Feishu's Markdown renderer pulls the `**` asterisks into the clickable link, breaking it. This applies to all Feishu-facing communication, not just published pages.

## References

- `scripts/serve.py` — unified HTTP server (static files + API proxy)
- `scripts/serve-watchdog.sh` — cron watchdog script
- `templates/light-theme.css` — shared theme CSS
