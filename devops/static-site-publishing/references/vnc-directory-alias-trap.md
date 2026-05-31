# VNC Directory Alias Trap

## The Problem

Writing HTML files to `/opt/data/www/vnc/` → 404 when accessed at `/vnc/<file>`.

## Root Cause

Local nginx config (`/etc/nginx/sites-enabled/workspace`):

```nginx
location /vnc/ {
    alias /opt/data/www/vnc/noVNC-1.5.0/;
    index vnc.html;
}
```

Any URL pattern `/vnc/*` is aliased to the noVNC directory. A file at `/opt/data/www/vnc/skill-report.html` accessed at `/vnc/skill-report.html` resolves to `/opt/data/www/vnc/noVNC-1.5.0/skill-report.html` → 404.

## Correct Pattern

Always write to `/opt/data/www/<slug>.html` — the web root. URL: `https://hermes-daqiezi.mergio.dev/<slug>.html`.

## Reproduction (2026-05-30)

1. Wrote three HTML files to `/opt/data/www/vnc/`
2. URLs like `/vnc/skills-plan.html` → 404
3. Checked nginx config → discovered `/vnc/` alias
4. Fixed: `mv /opt/data/www/vnc/*.html /opt/data/www/`
5. Verified: all three URLs returned 200
