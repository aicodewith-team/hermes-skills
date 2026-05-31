# Playwright E2E Setup Patterns

Tested on mergio-web (Next.js 16 + better-auth + next-intl + shadcn/ui). These patterns are reusable for any Next.js project.

## playwright.config.ts

```ts
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",
  fullyParallel: true,
  workers: 5,
  reporter: "html",
  use: { baseURL: "http://localhost:3000", trace: "on-first-retry" },
  projects: [
    { name: "chromium-desktop", use: { ...devices["Desktop Chrome"] } },
    // ⚠️ iPhone 13 uses WebKit — needs system deps on Linux (libgstreamer, etc).
    // Use Pixel 5 (Chromium-based) for Linux CI / test machines:
    { name: "chromium-mobile", use: { ...devices["Pixel 5"], defaultBrowserType: "chromium" } },
  ],
  webServer: [{
    // ⚠️ Use absolute path for pnpm — Playwright webServer may not inherit shell PATH
    command: "/opt/data/home/.npm-global/bin/pnpm dev",
    url: "http://localhost:3000",
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
    // Pass DB + app URL env vars so dev server can connect to DB and generate correct cookies
    env: {
      NEXT_PUBLIC_APP_URL: "http://localhost:3000",
      POSTGRES_HOST: "...",
      POSTGRES_PORT: "5432",
      POSTGRES_DB: "...",
      POSTGRES_USER: "...",
      POSTGRES_PASSWORD: "...",
      POSTGRES_SSL: "false",
    },
  }],
});
```

## Auth Fixture Pattern

For apps using cookie-based auth (better-auth, next-auth, lucia):

1. Seed a test user via the sign-up API in `beforeAll`
2. Extract the session cookie from the response headers
3. Inject via `context.addCookies()`
4. Clean up in `afterAll` (delete user + all related rows)

```ts
import { test as base } from "@playwright/test";

export const test = base.extend({
  authedPage: async ({ browser, request }, use) => {
    // request is the built-in APIRequestContext fixture (NOT base.request)
    const res = await request.post("/api/auth/sign-up/email", {
      data: { name: "Test", email: "...", password: "..." },
    });
    const setCookie = res.headers()["set-cookie"];
    const cookie = setCookie.split(",").find(c => c.startsWith("better-auth.session_token="));
    const [name, value] = cookie.split("=");

    const context = await browser.newContext();
    await context.addCookies([{ name, value, domain: "localhost", path: "/", httpOnly: true, secure: false, sameSite: "Lax" }]);
    const page = await context.newPage();
    await use(page);
    await context.close();
  },
});
```

### Pitfall: `base.request` vs fixture `request`

`base.request` is NOT the API request context — it doesn't have `.post()`. The `request` fixture must be destructured from the fixture function parameters:

```ts
// ❌ WRONG
async function createTestUser() {
  const res = await base.request.post("/api/...")  // base.request is not a function
}

// ✅ CORRECT
authedContext: async ({ browser, request }, use) => {
  const res = await request.post("/api/...")  // request from fixture params
}
```

## Selectors for i18n Pages

**Never use `getByRole('button', { name: /english text/i })` on i18n pages.** The visible text is translated and won't match English patterns.

```ts
// ❌ BROKEN — i18n translates "Sign In" to "登录" etc.
await page.getByRole("button", { name: /sign in/i }).click();

// ✅ WORKS — HTML attribute, not translated
await page.locator("button[type=submit]").click();

// ✅ Also works for input fields — use id, not label text
await page.locator("#email").fill("test@x.com");
await page.locator("#password").fill("pass");
```

### When getByRole DOES work

It works for:
- Links: `getByRole("link", { name: /sign in/i })` — if the href text is translated consistently
- Non-i18n button text (static strings)

But `button[type=submit]` is always safer for form submissions.

## DB Cleanup Order

When deleting a test user, respect FK constraints — delete children first:

```sql
DELETE FROM usage_records WHERE user_id = $1;
DELETE FROM workspace_tokens WHERE workspace_id IN (SELECT id FROM workspaces WHERE user_id = $1);
DELETE FROM hermes_workspace_events WHERE user_id = $1;
DELETE FROM workspaces WHERE user_id = $1;
DELETE FROM api_keys WHERE user_id = $1;
DELETE FROM subscriptions WHERE user_id = $1;
DELETE FROM session WHERE user_id = $1;
DELETE FROM account WHERE user_id = $1;
DELETE FROM "user" WHERE id = $1;
```

## Graceful Skip When Env Missing

Don't crash when DB/env is unavailable — `test.skip()` with a message:

```ts
try {
  sessionCookie = await createTestUser(request);
} catch (e) {
  console.warn(`Skipping authenticated tests: ${e}`);
  test.skip(true, `Cannot create test user: ${e}`);
  return;
}
```

## Screenshot Capture Script

For generating HTML reports with embedded screenshots, use a standalone Node script with playwright (not @playwright/test):

```js
const { chromium } = require("playwright");
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();
await page.goto("http://localhost:3000/en/login", { waitUntil: "networkidle" });
await page.screenshot({ path: "login.png", fullPage: true });
```

## better-auth: trustedOrigins for Local Testing

better-auth rejects requests from origins not in `trustedOrigins`. For Playwright tests hitting `localhost:3000`, you MUST add it:

```ts
// src/lib/auth.ts
export const auth = betterAuth({
  baseURL: process.env.NEXT_PUBLIC_APP_URL || "https://mergio.ai",
  trustedOrigins: [
    process.env.NEXT_PUBLIC_APP_URL || "https://mergio.ai",
    "http://localhost:3000",  // ← required for Playwright E2E
  ],
  // ...
});
```

Also set `NEXT_PUBLIC_APP_URL=http://localhost:3000` in the Playwright webServer env so better-auth generates cookies scoped to `localhost`, not the production domain. Without this, the session cookie domain won't match and auth checks will fail.

## PG MCP for Test DB Access (Password-Safe)

When DB credentials contain secrets you don't want in chat history or test config files, use mcporter + `mcp-server-postgres`:

```json
// ~/config/mcporter.json
{
  "mcpServers": {
    "postgres": {
      "command": "/path/to/mcp-server-postgres",
      "args": ["postgresql://user:pass@host:5432/db"]
    }
  }
}
```

**Important:** `mcp-server-postgres` expects a connection string as a CLI argument, NOT environment variables. mcporter auto-masks the password in its output (`***`).

Then use `mcporter call postgres.query sql="SELECT ..."` to run read-only queries. For test cleanup, use the app's own API endpoints (not direct DB writes — MCP postgres is read-only).

## Strict Mode Violation: Duplicate Links

When `getByRole('link', { name: /hermes/i })` matches BOTH a sidebar nav item AND a content-area link (e.g., "No workspace yet. Go to Hermes to create one."), Playwright throws strict mode violation.

**Fixes (pick one):**
```ts
// 1. Scope to the sidebar <nav> — most robust
await page.locator("nav").getByRole("link", { name: /hermes/i }).click();

// 2. Use .first()
await page.getByRole("link", { name: /hermes/i }).first().click();

// 3. Use exact match on the nav item
await page.getByRole("link", { name: "Hermes", exact: true }).click();
```

## Next.js Auth Guard: Server vs Client Component

Dashboard routes in Next.js App Router typically use **server component** auth guards:

```tsx
// ✅ Dashboard layout — server component, uses redirect()
export default async function DashboardLayout() {
  const session = await auth.api.getSession({ headers: await headers() });
  if (!session?.user) redirect(`/${locale}/login`);
  return <DashboardSidebar>...</DashboardSidebar>;
}
```

Login/signup pages are often **client components** (`"use client"`) and CANNOT call `redirect()`. If they lack an auth guard, authenticated users will see the login form instead of being redirected. This is a **code-missing** issue, not a test error.

**Patterns to add redirect guard to client-component auth pages:**

```tsx
// Option A: useEffect + authClient.getSession() (client-side)
"use client";
import { useEffect } from "react";
import { authClient } from "@/lib/auth-client";
import { useRouter } from "@/i18n/navigation";

export default function LoginPage() {
  const router = useRouter();
  useEffect(() => {
    authClient.getSession().then(({ data }) => {
      if (data?.user) router.push("/dashboard");
    });
  }, []);
  // ... rest of login form
}

// Option B: Next.js middleware.ts (catches before client render)
// middleware.ts
import { NextResponse } from "next/server";
export function middleware(request) {
  const sessionToken = request.cookies.get("better-auth.session_token");
  if (sessionToken && request.nextUrl.pathname.match(/\/(login|signup)/)) {
    return NextResponse.redirect(new URL("/dashboard", request.url));
  }
}
```

## Backend Dependency Tracing

When tests fail because API calls return errors, trace the full call chain to find missing env vars:

```
Test → /api/hermes/create (route.ts)
  → createWorkspaceForUser() (workspace-service.ts)
    → control.createRuntime() (control-client.ts)
      → ctrlUrl() — reads process.env.HERMES_CONTROL_URL
        → undefined → throw "HERMES_CONTROL_URL is not configured"
```

**Every `process.env.X` read in the backend chain is a potential failure point** when running locally. Check each one:

| Env Var | Read In | Purpose |
|---------|---------|---------|
| HERMES_CONTROL_URL | control-client.ts:17 | Hermes Control Plane API |
| HERMES_CONTROL_INTERNAL_TOKEN | control-client.ts:23 | Internal auth token |
| POSTGRES_* | db connection | Database access |
| NEXT_PUBLIC_APP_URL | auth.ts:6 | Cookie domain / trusted origins |

The fix: add all required vars to `playwright.config.ts → webServer[].env`. If a backend dependency (like Hermes Control Plane) is fundamentally unavailable, either mock the API or skip those tests.

### `.env.test` Pattern (Recommended Over Hardcoded Env)

Hardcoding secrets in `playwright.config.ts` is fragile. Use a `.env.test` file + dotenv:

```bash
# .env.test (gitignored — `.env*` already in .gitignore)
NEXT_PUBLIC_APP_URL=http://localhost:3000
POSTGRES_HOST=...
POSTGRES_PASSWORD=...
HERMES_CONTROL_URL=https://hermes-control.mergio.dev
HERMES_CONTROL_INTERNAL_TOKEN=...
# ... all env vars the dev server needs
```

```ts
// playwright.config.ts
import { config } from "dotenv";
config({ path: ".env.test" });

export default defineConfig({
  webServer: [{
    command: "/opt/data/home/.npm-global/bin/pnpm dev",
    env: {
      NEXT_PUBLIC_APP_URL: "http://localhost:3000",
      POSTGRES_HOST: process.env.POSTGRES_HOST!,
      POSTGRES_PASSWORD: process.env.POSTGRES_PASSWORD!,
      HERMES_CONTROL_URL: process.env.HERMES_CONTROL_URL!,
      // ... spread other vars from process.env
    },
  }],
});
```

Install dotenv as devDependency: `pnpm add -D dotenv`

Benefits:
- Single source of truth for test secrets
- `.gitignore` keeps it out of version control
- Easy to copy variables from Dokploy / production config
- `process.env.X!` gives type safety — missing vars fail fast

## Failure Triage Categories

When Playwright tests fail, classify before fixing. **Do NOT jump to fixes without root cause analysis.**

### Investigation Process

1. Read the full error message and stack trace
2. Read the test file to understand the expectation
3. Read the actual page/API component being tested
4. Trace API call chains to find where it breaks
5. Check environment variables propagated to the dev server

### Classification

| Category | Signal | Action |
|----------|--------|--------|
| **Test wrong** | Locator matches 0 or 2+ elements, wrong URL pattern, wrong assertion logic | Fix the test selector/timeout/expectation |
| **Code missing** | The feature being tested simply doesn't exist (e.g., login page has no redirect guard for authenticated users, API endpoint missing) | Add the feature or skip the test with a documented reason |
| **Env missing** | API returns 500/connection refused, `process.env.X` throws, backend dependency unreachable | Add env vars to webServer config, or mock the dependency |

### Real Examples from mergio-web

| Failure | Root Cause | Category |
|---------|-----------|----------|
| `getByRole('link', { name: /hermes/i })` strict mode violation | Content area has "No workspace yet. Go to Hermes" link that also matches | **Test wrong** |
| Login redirect: visiting `/login` with valid session stays on login page | Login page is `"use client"` with zero session check — guard was never implemented | **Code missing** |
| Hermes workspace never reaches "running" state | `HERMES_CONTROL_URL` not in webServer env → control-client throws → workspace stuck in "failed" | **Env missing** |
