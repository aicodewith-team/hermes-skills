---
name: static-site-publishing
description: >-
  ⚠️ MANDATORY when writing HTML files, creating reports, or publishing anything to hermes-daqiezi.mergio.dev. Triggers on: write_file .html, cp/mv to /opt/data/www, "生成HTML报告", "发布到公网", "给个链接", MEDIA file delivery, 飞书发 HTML 链接. HTML 页面从写到发布的完整流程。
tags: [html, publishing, static-site, reporting, feishu, theme]
platforms: [linux]
metadata:
  hermes:
    tags: [html, publishing, static-site, reporting, feishu, theme]
    related_skills: [nextjs-blog-ssg]
---

# Static Site Publishing — Hermes 本机环境

## ⛔ When This Skill MUST Be Loaded

**Any of these actions → load this skill BEFORE doing anything:**

| Trigger | Example |
|---|---|
| Writing any `.html` file | `write_file /opt/data/www/xxx.html` |
| Creating a report to share | "生成HTML报告", "给我HTML方案" |
| Copying/moving files to web root | `cp x.html /opt/data/www/` |
| Sending a link via Feishu | `https://hermes-daqiezi.mergio.dev/...` |
| MEDIA file delivery | `MEDIA:/opt/data/www/xxx.html` in message |

**To avoid: writing to wrong directory, 404 from /vnc/ alias trap, missing theme.css, forgetting sanitization check.**

> ⚠️ This skill is for **private reporting pages** (AI conversation reports, task results)
> served via nginx on `hermes-daqiezi.mergio.dev`.
> For **public SEO/blog pages** on the main site, use the `nextjs-blog-ssg` skill instead —
> it shares the main site's Navigation + Footer for design consistency.

## 核心行为规则

1. **任务完成默认出 HTML 报告** — 做完任何有产出的任务，生成 HTML 报告页发布公网。飞书里只发链接 + 一句话，不堆字。
2. **复杂决策用交互表单** — 需要用户选型/排序/确认时，生成交互式 HTML 表单，不走飞书追问。末尾必须有「导出 Markdown」按钮。
3. **发布前必然 sanitization** — 公网可见，绝对不能不检查就发。
4. ⚠️ **这不是 MERGIO 公开博客** — 这是大茄子（Hermes Agent）的私有任务报告站。MERGIO 产品公开博客使用 `mergio-blog-ssg` skill（SSG + Next.js pages，和主站共享 layout）。不要把产品博客文章发到这个域名。

## 快速参考

| 项目 | 值 |
|------|----|
| **域名** | `hermes-daqiezi.mergio.dev` |
| **静态文件根目录** | `/opt/data/www` |
| **Web 服务器** | nginx (`/usr/sbin/nginx`)，容器内 80 端口 |
| **nginx 站点配置** | `/etc/nginx/sites-enabled/workspace` |
| **主题 CSS** | `/opt/data/www/theme.css` |
| **交互组件 CSS** | `/opt/data/www/interaction.css` |
| **交互模板** | `/opt/data/www/interaction-patterns.html` |
| **反向代理** | Dokploy 管理的 Traefik（宿主机 38.190.178.92:80/443） |
| **容器名** | `daqiezi-hermes` |

## 架构

```
用户 → https://hermes-daqiezi.mergio.dev
       │
       ▼
Dokploy Traefik (宿主机 38.190.178.92:443, TLS 终止)
       │
       ▼ Docker 网络 → daqiezi-hermes 容器
       │
nginx :80 (容器内 root 启动)
       │
       ├── root /opt/data/www (try_files $uri $uri.html $uri/index.html =404)
       ├── location /vnc/ → alias /opt/data/www/vnc/noVNC-1.5.0/
       └── location /websockify → proxy_pass http://127.0.0.1:6080/
```

**关键点:**
- 静态站点由容器内 **nginx** 直接 serve（不再是 serve.py）
- nginx 以 root 身份运行在容器内 80 端口（由 Docker entrypoint 在 `gosu hermes` 前启动）
- Traefik 负责 TLS 终止 + 域名路由，通过 Docker 网络直连容器
- serve.py 已退役；`serve-watchdog.sh` 已禁用（`/opt/data/scripts/serve-watchdog.sh.disabled`）
- 容器重启后 nginx 自动启动（entrypoint 已配置）

---

## ⚠️ 主题规则（必读）

本 Skill 覆盖 `hermes-daqiezi.mergio.dev`，**必须引用亮色主题**：

| 域 | 主题 | CSS |
|---|------|-----|
| `hermes-daqiezi.mergio.dev` | **亮色（默认）** | `/theme.css`（白底 `#ffffff`） |

**铁律：页面必须引用 theme.css（亮色），不能自己写暗色样式。**

## Part 1: 页面类型与规范

本 Skill 覆盖三种 HTML 页面：

### 类型 A: 产品介绍 / 汇报页

给人看的，不是技术文档裸转。**必须包含以下结构:**

1. **Hero** — 一句话说清这是什么
2. **Why** — 为什么需要这个东西（痛点）
3. **How It Works** — 怎么运行的（流程图/步骤）
4. **对比 / 卖点** — 和竞品或现状的区别
5. **定价** (如适用)
6. **FAQ** — 常见疑问

要讲前因后果，让读者看完就理解这个产品是干什么的、为什么选择它。

### 类型 B: 交互式决策表单

需要用户做复杂决策时使用（项目配置、架构选型、功能排期、优先级排序等）。

**适用场景:** 项目初始化（技术栈选择）、架构决策（数据库选型）、功能优先级（拖拽排序）、配置确认（多选模块 + 开关 + 滑块）、任何需要用户做 3+ 个选择的复杂决策。

**硬性规则:**
- 末尾**必须有「导出 Markdown」按钮**
- 用户操作完 → 点按钮 → 生成结构化 Markdown → 复制粘贴回来
- Markdown 格式必须包含 3 段：标题+时间戳 → 分类回答 →「需要我做什么」

**CSS 引用:**
```html
<link rel="stylesheet" href="/theme.css">
<link rel="stylesheet" href="/interaction.css">
```

`/opt/data/www/interaction.css` 包含所有交互组件的样式（单选卡片、复选卡片、拖拽排序、开关、滑块、条件展开、导出区）。

**可用组件:**

1. **单选卡片** — 排他选择
```html
<div class="choice-group" id="myChoice">
  <div class="choice-card selected" onclick="pickOne(this, 'myChoice')">
    <div class="radio-dot"></div>
    <div><div class="choice-title">选项 A</div><div class="choice-hint">描述</div></div>
  </div>
</div>
```
JS: `pickOne(el, groupId)` — 清同组 `.selected`，给当前加 `.selected`

2. **复选卡片** — 多选组合
```html
<div class="check-card checked" onclick="this.classList.toggle('checked')">
  <div class="check-icon">✓</div>
  <span class="check-label">PostgreSQL</span>
</div>
```
⚠️ **不要用 `<label>` 标签！** `<label>` 内置 checkbox 切换行为，与 `classList.toggle('checked')` 冲突，会导致点击无反应或状态错乱。直接用 `<div>` + `onclick` + `classList.toggle`。

3. **拖拽排序** — 优先级/排名（蓝色线显示插入位置：上方=插前面，下方=插后面）
```html
<div class="drag-list" id="dragList">
  <div class="drag-item" draggable="true">
    <span class="drag-handle">⠿</span>
    <span class="drag-rank">1</span>
    <span class="drag-text">功能名称</span>
    <span class="drag-delete" onclick="removeDragItem(this); event.stopPropagation()" title="移除">✕</span>
  </div>
</div>
```
⚠️ **JS 必须从 `/opt/data/www/interaction-patterns.html` 照抄**，不要手写。核心：`insertBefore` 原地重排，`clearAllIndicators()` 统一清理，IIFE 包裹。`dragstart` 里**必须**调 `e.dataTransfer.setData('text/plain', '')`（Firefox 硬要求，缺了拖拽完全不触发）。CSS 用 `drag-over-before` / `drag-over-after` 伪元素画插入线，**不要**自创 `drag-over` 类。

**拖拽项删除按钮（可选）** — 每行右侧加 ✕：
```html
<span class="drag-delete" onclick="removeDragItem(this); event.stopPropagation()" title="移除">✕</span>
```
CSS:
```css
.drag-delete { margin-left: auto; width: 22px; height: 22px; border-radius: 50%; background: transparent; color: var(--text2); display: flex; align-items: center; justify-content: center; font-size: 12px; font-weight: 700; cursor: pointer; transition: all 0.15s; }
.drag-delete:hover { background: var(--red); color: #fff; }
```
JS: `removeDragItem(btn)` — `btn.closest('.drag-item').remove()` 后重算 rank。`onclick` 里必须 `event.stopPropagation()` 防止触发拖拽。

4. **开关切换** — 是/否
```html
<div class="toggle-switch on" onclick="this.classList.toggle('on')"></div>
```

5. **滑块** — 程度/预算
```html
<input type="range" class="slider-bar" min="0" max="100" value="50"
  oninput="document.getElementById('val').textContent=this.value">
```

6. **条件展开** — 选 A 才问 B
```html
<div class="conditional-child visible">...</div>
```
JS: 检查选中项后 `child.classList.toggle('visible', condition)`

**键盘支持:** `Ctrl+Enter` / `Cmd+Enter` 触发生成 Markdown。

**模板参考:** `/opt/data/www/interaction-patterns.html`（6 种模式的完整演示，含导出按钮 + Markdown 复制）

### 类型 C: 任务结果报告页

任务完成后的成果展示页。结构模板：

1. **结果摘要** — 一句话 + 关键数字（用时、文件数、测试通过率等）
2. **做了什么** — 3-5 个 bullet，每个一句话
3. **关键产出** — 文件清单、链接、截图
4. **验证方法** — 用户怎么确认成果（curl 命令、URL、截图）

风格：简洁直给，不展开讨论，不放过程细节。

---

## Part 2: 发布流程

### Step 1: ⚠️ 先加载此 Skill — 不要凭记忆操作

**铁律：发布 HTML 前必须先 `skill_view('static-site-publishing')` 加载此 Skill。**

常见翻车场景（每次不看 skill 必犯）：
- **写错目录** → `~/.hermes/public/` 或 `mergio-web/public/` — 实际是 `/opt/data/www/`
- **发错 URL** → `hermes.mergio.ai/public/` — 实际是 `hermes-daqiezi.mergio.dev/`
- ⚠️ **写到 `/opt/data/www/vnc/` 目录** → 本机 nginx 把 `/vnc/` alias 到了 noVNC 目录（`/opt/data/www/vnc/noVNC-1.5.0/`），写到 `/opt/data/www/vnc/some.html` 的请求 `/vnc/some.html` 会去 noVNC 目录找 → 404。正确路径永远是 `/opt/data/www/<slug>.html`
- 写错目录 → 404 → 浪费时间排查。加载 Skill 只需 1 秒，排查路径错误至少 30 秒。

### Step 2: 写 HTML 页面

保存到 `/opt/data/www/<slug>.html`。

页面基本要求:
- **⚠️ 必须引用共享主题: `<link rel="stylesheet" href="/theme.css">`** — 禁止自己写内联暗色样式。theme.css 是亮色主题，所有页面的视觉一致性依赖这条引用。不要自作主张生成暗色页面。
- UTF-8 编码: `<meta charset="utf-8">`
- 移动端必须加 `@media (max-width: 640px)` 让 flex 列变成纵向堆叠

**theme.css 已有的类（直接使用，不用在页面 `<style>` 里重新定义）：**
- `.header` + `.badge` — 页面头部
- `.card-grid` + `.card` — 卡片网格
- `.highlight-box` — 高亮结论框
- `.timeline` + `.timeline-item` — 时间线
- `.table-wrap` + `table` — 表格（含 thead 背景色、nth-child 斑马纹、链接色 var(--accent)）
- `.principle-grid` / `.grade-grid` + `.principle-card` / `.grade-card` — 对比卡片和等级卡片
- `footer` — 页脚

**需要在页面 `<style>` 里自建的类（theme.css 没有，从下方模板复制）：**

**⚠️ `.code-block` 和 `.dir-tree` — 代码块和目录树（theme.css 里没有！每个页面必须自建）**

```css
.code-block { background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 14px 16px; font-family: "SF Mono","Fira Code","Cascadia Code","JetBrains Mono",monospace; font-size: 13px; line-height: 1.7; white-space: pre-wrap; word-break: break-word; overflow-x: auto; margin: 12px 0; }
.dir-tree { background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 14px 16px; font-family: "SF Mono","Fira Code","Cascadia Code","JetBrains Mono",monospace; font-size: 13px; line-height: 1.7; white-space: pre; overflow-x: auto; margin: 12px 0; color: var(--text); }
.dir-tree strong { color: var(--accent); }
```

**⚠️ 字体栈必须明确** — 不能用裸 `font-family: monospace`。在 Linux 上 box-drawing 字符 `├──` `└──` 的 glyph 宽度不等于 ASCII 宽度，连线会断开。必须用上面的完整 monospace 栈。

**⚠️ 目录树用 `<pre class="dir-tree">`，代码块用 `<div class="code-block">`** — `<pre>` 自带 `white-space: pre`，天然适合保留换行和缩进的目录树，无需额外 CSS 控制换行行为。

**`.arch-box` / `.arch-layer` / `.arch-arrow` — 架构图（替代 ASCII 字符画）**

```css
.arch-diagram { display: flex; flex-direction: column; gap: 16px; margin: 20px 0; font-size: 13px; }
.arch-layer { border: 1px solid var(--border); border-radius: 8px; padding: 14px 16px; background: var(--surface); }
.arch-layer h4 { margin: 0 0 6px; font-size: 12px; text-transform: uppercase; color: var(--text2); }
.arch-layer p { margin: 0; }
.arch-arrow { text-align: center; color: var(--text2); font-size: 18px; margin: -6px 0; }
.arch-layer.mergio-web { border-left: 3px solid var(--accent); }
.arch-layer.control-plane { border-left: 3px solid var(--blue); }
.arch-layer.external { border-left: 3px solid var(--amber); }
.arch-layer.hermes { border-left: 3px solid var(--green); }
```

**`.codespan` — 内联代码片段**

```css
.codespan { background: var(--surface2); padding: 1px 6px; border-radius: 3px; font-family: "SF Mono","Fira Code","Cascadia Code","JetBrains Mono",monospace; font-size: 12px; }
```

**`.tag` — 状态标签**

```css
.tag { display: inline-block; font-size: 10px; padding: 2px 8px; border-radius: 12px; font-weight: 700; margin-right: 4px; }
.tag-ok { background: #d4edda; color: #155724; }
.tag-gap { background: #fce4d6; color: #c65911; }
.tag-new { background: #e2d9f3; color: #6741d9; }
```

**默认排版约定（theme.css 已设定，无需页面自建）：**
- 正文字体: `system-ui, -apple-system, sans-serif`
- 正文行高: `1.6`
- h1: 1.75rem, h2: 1.4rem, h3: 1.15rem, h4: 1rem
- `p` 间距: `0 0 0.75em`
- 链接色: `var(--accent)`，hover 加下划线
- 移动端断点: `640px`（固定约定）

### Step 2: ⚠️ 安全检查 + 主题检查 — 必须执行, 不可跳过

```bash
# 1. 密钥检查（命中包括字段名如 api_key、token — 人工审核确认无实际密钥值即可）
grep -nE "(sk-|whsec_|api_key|password|token|secret|key_value|http://127\.|http://10\.|http://192\.168\.|DATABASE_URL=)" /opt/data/www/<slug>.html

# 2. 主题检查 — hermes-daqiezi 页面必须引用亮色 theme.css
if grep -q 'theme.css' /opt/data/www/<slug>.html; then echo "✅ 主题检查通过"; else echo "❌ 缺少 theme.css 引用！"; fi
```

- **grep 密钥命中实际 key 值 → 🔴 阻断发布**，必须先清理。如命中仅为字段名/代码片段（如 `telegram_bot_token`、`aicodewith_api_key`），人工审核确认无泄露值后可通过。
- **grep 主题无输出 → 🔴 阻断发布**，页面缺少 `<link rel="stylesheet" href="/theme.css">` 引用。不要自作主张写内联暗色样式，补上 theme.css 引用。
- **两个检查都通过 → ✅ 通过**

### Step 3: 验证公网可访问

```bash
curl -sI https://hermes-daqiezi.mergio.dev/<slug>.html | head -3
```

HTTP 200 = 上线成功。

如果返回 404:
- 检查文件名是否在 `/opt/data/www/` 目录下
- URL 大小写敏感: `/Org-OS` 不匹配 `org-os.html`
- nginx 是否在运行: `ssh root@38.190.178.92 "docker exec daqiezi-hermes pgrep nginx"`

### Step 5: 通知用户

飞书消息发:
- 页面 URL (不要加粗，裸发)
- 一句话描述

---

## Part 3: 主题 CSS 参考

### 变量

| 变量 | 默认值 | 用途 |
|------|--------|------|
| `--bg` | `#ffffff` | 页面背景 |
| `--surface` | `#f8f9fa` | 卡片/区块背景 |
| `--surface2` | `#e9ecef` | 表格头/次要背景 |
| `--border` | `#dee2e6` | 边框 |
| `--text` | `#212529` | 正文 |
| `--text2` | `#6c757d` | 次要文字 |
| `--accent` | `#7c3aed` | 主色调 (紫色) |
| `--accent2` | `#6c5ce7` | 辅助色 |
| `--red` | `#dc3545` | 危险/扣除 |
| `--green` | `#198754` | 成功/奖励 |
| `--amber` | `#e6a817` | 警告 |
| `--blue` | `#0d6efd` | 信息 |

### 预置组件（theme.css 里已有的类 — 直接用）

- `.header` + `.badge` — 页面头部（左对齐、底部横线）
- `.card-grid` + `.card` — 卡片网格（2/3/4 列自适应，卡片带圆角阴影）
- `.highlight-box` — 高亮结论框（左侧紫色边框 + 浅紫背景）
- `.timeline` + `.timeline-item` — 时间线（竖线 + 圆点）
- `.table-wrap` + `table` — 表格（滚动容器 + thead 灰底 + 斑马纹 + 链接自动 var(--accent)）
- `.principle-grid` + `.principle-card` — 原则对比卡片
- `.grade-grid` + `.grade-card` — 评分等级卡片
- `footer` — 页脚

### 需在页面 `<style>` 自建的组件（theme.css 里没有，从 Part 2 模板复制）

- `.code-block` — 代码块
- `.dir-tree` — 目录树（用 `<pre>` 标签）
- `.arch-box` / `.arch-layer` / `.arch-arrow` — 架构图
- `.codespan` — 内联代码
- `.tag` / `.tag-ok` / `.tag-gap` / `.tag-new` — 状态标签

页面 `<style>` 只放上述自建类 + 页面专属样式，不重新定义 theme.css 已有的变量和组件。

### 移动端适配

```css
@media (max-width: 640px) {
  .branch-container { flex-direction: column !important; }
  .card-grid { grid-template-columns: 1fr; }
}
```

### Code Block & 目录树

完整 CSS 模板见 Step 2 的「需在页面 `<style>` 里自建的类」段落，从那里复制。

关键规则：
- 代码块用 `<div class="code-block">`，目录树用 `<pre class="dir-tree">`
- `<pre>` 自带 `white-space: pre`，目录树不需要额外处理换行；`<div>` 需要 `white-space: pre-wrap`
- 字体栈必须明确 — 裸 `monospace` 在 Linux 上会导致 box-drawing 字符 `├` `─` `└` 宽度错位，连线断开

---

## Part 4: nginx 运维

**注意：nginx 运行在 `daqiezi-hermes` 容器内，以 root 身份启动（80 特权端口）。hermes 用户无权直接操作！**

### 检查状态
```bash
# 从宿主机检查
ssh root@38.190.178.92 "docker exec daqiezi-hermes pgrep -a nginx"
```

### 重启 nginx
```bash
ssh root@38.190.178.92 "docker exec daqiezi-hermes /usr/sbin/nginx -s reload"
```

### nginx 挂了怎么办
```bash
ssh root@38.190.178.92 "docker exec -d daqiezi-hermes /usr/sbin/nginx"
```

### 测试配置
```bash
ssh root@38.190.178.92 "docker exec daqiezi-hermes /usr/sbin/nginx -t"
```

### 配置文件
- 主配置: `/etc/nginx/nginx.conf`
- 站点: `/etc/nginx/sites-enabled/workspace`
- 日志: `/var/log/nginx/access.log`, `/opt/data/logs/nginx-error.log`

---

## 添加新域名

1. DNS 添加 A 记录指向 `38.190.178.92`
2. Dokploy Traefik 添加路由规则指向 `daqiezi-hermes` 容器（Docker 网络）
3. nginx 站点配置无需修改（`server_name _` 匹配所有域名）

---

### ⚠️ nginx 文件优先级陷阱

nginx 的 `try_files` 有固定优先级：

```
请求 /mergio-e2e-report/
  → 1. /mergio-e2e-report.html （文件优先！）
  → 2. /mergio-e2e-report/index.html （目录次之）
```

**如果同时存在 `slug.html` 和 `slug/index.html`，`.html` 文件永远胜出。** 常见场景：之前部署了一个独立的 Playwright 自定义报告 `mergio-e2e-report.html`，后来又部署了 Playwright 原生报告到 `mergio-e2e-report/index.html`。公网访问到的永远是旧文件。

**解决：** `rm /opt/data/www/mergio-e2e-report.html` 删掉旧文件，目录 `index.html` 才会生效。

### ⚠️ Playwright 报告是多文件

Playwright 原生 HTML 报告不是单文件 — 包含 `index.html` + `data/` 目录（JSON 数据）。部署时必须整个目录复制：

```bash
mkdir -p /opt/data/www/mergio-e2e-report
cp -r playwright-report/* /opt/data/www/mergio-e2e-report/
```

只复制 `index.html` 会导致报告页面空白（缺少 data/ 下的 JSON）。

### ⚠️ Dokploy autoDeploy 覆盖本地

当 Dokploy 应用启用 `autoDeploy: true` 时，任何 push 到仓库的 commit 都会触发部署同步，**覆盖本地工作树**。如果有人在远端 commit 了删除测试文件的操作，本地 `git pull` 会静默删除所有未提交的本地修改。

**防护：** 在 mergio-web 这种 autoDeploy 项目里做测试开发时，把测试文件 git add 并 stash，或者开新分支。

---

### ⚠️ 禁止 ASCII 字符画做架构图

在 HTML 报告里用 ASCII art（`┌─┐└─┘│├┤ ◄─►`）画架构图不行。用原生 HTML/CSS 分层盒子 + border 颜色编码来展示。使用 Part 2 中定义的 `.arch-diagram` / `.arch-layer` / `.arch-arrow`（从模板复制 CSS）。不要生成 `<pre>` 包裹的 ASCII 图。

## 常见问题

| 问题 | 原因 | 解决 |
|------|------|------|
| 公网访问到旧内容 | `slug.html` 文件存在，覆盖了 `slug/index.html` | `rm /opt/data/www/slug.html` 删掉旧文件 |
|------|------|------|
| 公网 404 | 文件名不存在或大小写不匹配 | `ls /opt/data/www/`, URL 大小写敏感 |
| 公网 404（`/vnc/*` 路径） | 文件写到了 `/opt/data/www/vnc/` — nginx 把 `/vnc/` alias 到了 noVNC 目录，不会从这里 serve 文件 | 文件移到 `/opt/data/www/` 根目录，URL 不要带 `/vnc/` 前缀 |
| 公网 502 | nginx 挂了 | `ssh root@38.190.178.92 "docker exec -d daqiezi-hermes /usr/sbin/nginx"` |
| code block 乱码 | 缺少 `white-space: pre-wrap` | 加 CSS |
| 手机排版爆炸 | 并排元素没做响应式 | 加 `@media` |
| 长 URL 溢出 | 缺少 `word-break` | 加 `word-break: break-word` |
| 飞书链接打不开 | URL 被加粗 | 裸发 URL, 不加 `**` |
| 页面变成暗色主题 | 没引用 theme.css，自己写了内联暗色样式 | 加上 `<link rel="stylesheet" href="/theme.css">`，删掉内联暗色变量 |
| 复选框点不动 | 用了 `<label>` + 隐藏 `<input>` | 改用 `<div>` + `onclick` + `classList.toggle` |
| 拖拽没反应 | 忘了设 `draggable="true"` 或 `dragstart` 里缺 `e.dataTransfer.setData('text/plain', '')`（Firefox 必须） | 加 `draggable="true"` + `setData` |
| 拖拽完 rank 没更新 | drop 后没调 `updateRanks()` | dragend 和 drop 末尾都调 |
| 拖拽时蓝线残留 | `dragover` 提前 `return` 前没调 `clearAllIndicators()` | 先 `clearAllIndicators()` 再 `return` |
| 移动端拖拽无效 | 移动浏览器不支持 HTML5 DnD | 降级为点击排序（加 ↑↓ 按钮） |
| noVNC WebSocket 连不上 | websockify 挂了 | `ssh root@38.190.178.92 "docker exec daqiezi-hermes pgrep -a websockify"`，如果没输出则启动: `ssh root@38.190.178.92 "docker exec -d daqiezi-hermes websockify 0.0.0.0:6080 localhost:5901"` |

## E2E 测试

Playwright E2E 测试的完整模式（auth fixture、i18n 选择器、DB 清理）见 `references/playwright-e2e-setup.md`。

## 公共 SEO 博客

This skill is for **private reporting pages** on `hermes-daqiezi.mergio.dev`.
For public SEO/blog pages on the main MERGIO site (`mergio.ai`), use the `nextjs-blog-ssg` skill —
it achieves perfect layout consistency by sharing the main site's Navigation + Footer via Next.js SSG.
