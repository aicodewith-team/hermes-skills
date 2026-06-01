---
name: static-site-publishing
description: >-
  ⚠️ MANDATORY when writing HTML files, creating reports, or publishing to hermes-daqiezi.mergio.dev (本机) or via /publish/ namespace (Workspace). Triggers on: write_file .html, "生成HTML报告", "发布到公网", "给个链接".
tags: [html, publishing, static-site, reporting, feishu, theme]
platforms: [linux]
metadata:
  hermes:
    tags: [html, publishing, static-site, reporting, feishu, theme]
    related_skills: [nextjs-blog-ssg]
---

# Static Site Publishing

## ⚠️ 环境检测

本 Skill 绑定 daqiezi-hermes 本机环境（nginx + Traefik + DNS）。如果在 Mergio workspace 容器中（Nomad 管理），发布流程不同。

```bash
echo "${WORKSPACE_ID:-not-set}"
```

| WORKSPACE_ID | 环境 | 走哪条路径 |
|---|---|---|
| not-set | daqiezi-hermes 本机 | 本文 Part 1-4 → `hermes-daqiezi.mergio.dev` |
| 已设置 | Mergio Workspace 容器 | 跳到 **Part 0**（Web Server StaticFiles + 控制面代理） |

## When This Skill MUST Be Loaded

| Trigger | Example |
|---|---|
| Writing any `.html` file | `write_file /opt/data/www/xxx.html` 或 `write_file $HERMES_HOME/public/xxx.html` |
| Creating a report | "生成HTML报告", "给我HTML方案" |
| Copying files to web root | `cp x.html /opt/data/www/` 或 `cp x.html $HERMES_HOME/public/` |
| Sending a link via Feishu | `https://hermes-daqiezi.mergio.dev/...` 或 `https://hermes-runtime.aicodewith.com/workspaces/...` |

## 快速参考

| 项目 | 值 |
|---|---|
| **域名** | `hermes-daqiezi.mergio.dev` |
| **静态文件根目录** | `/opt/data/www` |
| **Web 服务器** | nginx (`/usr/sbin/nginx`)，容器内 80 端口 |
| **主题 CSS** | `/opt/data/www/theme.css` |
| **交互 CSS** | `/opt/data/www/interaction.css` |
| **骨架模板** | `templates/report-base.html` |
| **交互组件模板** | `templates/interaction-components.html` |
| **校验脚本** | `scripts/validate-html.sh` |
| **容器名** | `daqiezi-hermes` |

## 主题规则

**铁律：hermes-daqiezi.mergio.dev 所有页面必须引用亮色 theme.css。禁止自建 :root 变量、禁止暗色背景。**

## Part 0: Workspace 发布（Mergio Workspace 容器）

Workspace 容器走 **Hermes web_server.py StaticFiles + 控制面代理** 路径发布。无需 nginx、无需独立域名、无需 DNS 配置。

### 文件写入路径

```
$HERMES_HOME/public/<slug>.html
```

- `$HERMES_HOME` 在 workspace 中指向 `/hermes-cloud/workspaces/{id}/agents/default/hermes-home`
- 该目录在 Nomad host volume 上 → 容器重启不丢
- 目录会在首次写入时自动创建（Starlette StaticFiles 行为）

### 公网 URL

```
https://hermes-runtime.aicodewith.com/workspaces/{WORKSPACE_ID}/publish/<slug>.html
```

> ⚠️ 如果不知道 `WORKSPACE_ID`，用 `echo "${WORKSPACE_ID:-unknown}"` 获取。

### 验证公网可访问

```bash
curl -sI "https://hermes-runtime.aicodewith.com/workspaces/${WORKSPACE_ID}/publish/<slug>.html" | head -3
```

HTTP 200 = 上线成功。

### 发布步骤（简化版）

1. **写文件** → `$HERMES_HOME/public/<slug>.html`
2. **安全校验** → 同 Part 2 Step 3（密钥检查）
3. **验证 URL** → `curl -sI https://...`
4. **通知用户** → 发 URL（裸发，不加粗）

### 与 daqiezi-hermes 本机的差异

| | daqiezi-hermes 本机 | Workspace 容器 |
|---|---|---|
| 文件路径 | `/opt/data/www/` | `$HERMES_HOME/public/` |
| 公网域名 | `hermes-daqiezi.mergio.dev` | `hermes-runtime.aicodewith.com/workspaces/{id}/publish/` |
| Web Server | nginx :80 | Hermes web_server.py :9119 StaticFiles |
| theme.css | `/opt/data/www/theme.css` | ⚠️ 无共享主题文件。页面必须自包含全部 CSS（内联 `<style>` 或引用共享 CDN） |
| nginx 运维 | `ssh root@38.190.178.92 ...` | ❌ 不适用，跳过所有 nginx/SSH 命令 |
| 文件持久化 | Host volume | Nomad host volume（同节点持久化） |

### ⚠️ Workspace 模式关键提醒

- **不可引用 `/theme.css`** — workspace 容器的 `/opt/data/www/` 没有这个文件。CSS 全部写在页面 `<style>` 里。
- **不可用 `ssh`** — workspace 容器没有 SSH 访问宿主机的权限。
- **不可用 `hermes-daqiezi.mergio.dev` 域名** — DNS 指向另一台机器。
- **文件路径必须用 `$HERMES_HOME/public/`** — 不能写 `/opt/data/www/`（未 serve、不持久）。

---

## Part 1: 页面类型 & 模板选择

**生成任何 HTML 前，先选模板：**

| 报告类型 | 用哪个模板 | 说明 |
|---|---|---|
| 技术分析报告 | `templates/report-analysis.html` | 评估、对比、调研、根因分析 |
| 执行计划报告 | `templates/report-plan.html` | 功能开发、架构迁移、分阶段方案 |
| 任务完成报告 | `templates/report-task.html` | Bug 修复、功能交付、排障完成 |
| 交互式决策表单 | `templates/interaction-components.html` | 选型、排序、配置确认 |
| 自定义 | `templates/report-base.html` | 不匹配上述时，用骨架自己写 CONTENT |

**使用方式：** 复制骨架 → 替换占位符 → 参考内容模板的结构 → 填充。骨架内置了全部自建 CSS、响应式、文字批注系统。

### 交互式表单专属步骤

**⛔ JS 必须从 `templates/interaction-components.html` 照抄，禁止手写。**

1. 复制 `report-base.html` → `<head>` 加 `<link rel="stylesheet" href="/interaction.css">`
2. 从模板「STEP 2」复制需要的组件 HTML（单选/复选/拖拽/开关/滑块/条件展开）
3. 从模板「STEP 3」复制整段 `<script>`（`pickOne`、`HermesIO`、拖拽排序）
4. 页面专属 JS 里只写 `HermesIO.register('问题名', getter)` 注册导出字段

**组件速查：**

| 组件 | 关键类名 | 用法 |
|---|---|---|
| 单选 | `.choice-group` + `.choice-card` | `onclick="pickOne(this,'gid')"` |
| 复选 | `.check-group` + `.check-card` | `onclick="this.classList.toggle('checked')"`，禁用 `<label>` |
| 拖拽 | `.drag-list` + `.drag-item` | JS 自动绑定，无需手动初始化 |
| 开关 | `.toggle-row` + `.toggle-switch` | `onclick="this.classList.toggle('on')"` |
| 滑块 | `.slider-bar` | 标准 `<input type="range">` |
| 条件展开 | `.conditional-child` | JS 控制 `.visible` |
| 导出 | `.export-section` + `.result-block` | `HermesIO.export()` / `HermesIO.copy()` |

---

## Part 2: 发布流程

### Step 1: 加载此 Skill

**铁律：发布 HTML 前必须先 `skill_view('static-site-publishing')`。**

### Step 2: 复制骨架模板

```bash
cp /opt/data/skills/devops/static-site-publishing/templates/report-base.html /opt/data/www/<slug>.html
```

用 `patch` 替换占位符：`{{TITLE}}` `{{SLUG}}` `{{BADGE}}` `{{H1}}` `{{SUBTITLE}}` `{{HEADER_EXTRA}}` `{{PAGE_CSS}}` `{{MOBILE_CSS}}` `{{DATE}}` `{{CONTENT}}`。

**禁止：** 手写 `<html>` `<head>` `<body>` 标签、内联 `max-width`、自建 `:root`、暗色主题。

模板已内置：UTF-8、viewport、`<link href="/theme.css">`、`<main class="container">`、全部自建 CSS（`.code-block` `.codespan` `.tag` `.arch-diagram` `.step` 等）、移动端响应式、footer、**文字批注系统**（选中→💬→卡片输入→高亮→hover 查看→导出）。

theme.css 已有的类直接使用（`.header` `.card-grid` `.card` `.highlight-box` `.timeline` `.table-wrap` `footer`），不要在 `{{PAGE_CSS}}` 里重新定义。

### Step 3: 校验（阻断级）

```bash
# 样式合规
bash /opt/data/skills/devops/static-site-publishing/scripts/validate-html.sh /opt/data/www/<slug>.html

# 密钥检查
grep -nE "(sk-|whsec_|api_key|password|token|secret|key_value|http://127\.|http://10\.|http://192\.168\.|DATABASE_URL=)" /opt/data/www/<slug>.html
```

两项检查不通过 → 阻断发布。

### Step 4: 验证公网

```bash
curl -sI https://hermes-daqiezi.mergio.dev/<slug>.html | head -3
```

### Step 5: 通知用户

发 URL（裸发，不加粗）+ 一句话描述。

---

## Part 3: 主题 CSS 变量

| 变量 | 值 | 变量 | 值 |
|---|---|---|---|
| `--bg` | `#ffffff` | `--accent` | `#7c3aed` |
| `--surface` | `#f8f9fa` | `--accent2` | `#6c5ce7` |
| `--surface2` | `#e9ecef` | `--red` | `#dc3545` |
| `--border` | `#dee2e6` | `--green` | `#198754` |
| `--text` | `#212529` | `--amber` | `#e6a817` |
| `--text2` | `#6c757d` | `--blue` | `#0d6efd` |

移动端断点: `@media (max-width: 640px)`。

---

## Part 4: nginx 运维

**nginx 运行在 daqiezi-hermes 容器内 root 身份。hermes 用户无权操作。**

```bash
# 检查状态
ssh root@38.190.178.92 "docker exec daqiezi-hermes pgrep -a nginx"

# 重启
ssh root@38.190.178.92 "docker exec daqiezi-hermes /usr/sbin/nginx -s reload"

# 启动（挂了时）
ssh root@38.190.178.92 "docker exec -d daqiezi-hermes /usr/sbin/nginx"
```

配置：主配置 `/etc/nginx/nginx.conf`，站点 `/etc/nginx/sites-enabled/workspace`。

### ⚠️ nginx try_files 优先级

`slug.html` 文件 > `slug/index.html` 目录。同时存在时文件胜出。

### ⚠️ Dokploy autoDeploy

启用 autoDeploy 的仓库，远端 commit 会覆盖本地工作树。在 mergio-web 等项目中测试时，先 git add + stash 或开新分支。

---

## 常见问题

| 问题 | 原因 | 解决 |
|---|---|---|
| 公网 404 | 文件名不存在或大小写不匹配 | `ls /opt/data/www/`，URL 大小写敏感 |
| 公网 404（`/vnc/*`） | 文件写到了 `/opt/data/www/vnc/` | 移到 `/opt/data/www/` 根目录 |
| 公网 502 | nginx 挂了 | `ssh root@… "docker exec -d daqiezi-hermes /usr/sbin/nginx"` |
| 页面不居中/暗色/结构飞了 | Agent 没加载 Skill，凭记忆手写 | ⛔ 必须加载 Skill + 复制骨架模板 |
| 代码块 HTML 实体渲染异常 | `<pre>` 里 `<!--` 转了但 `-->` 没转 | 全部 HTML 特殊字符必须转义 |
| 交互组件 JS 行为异常 | Agent 手写了 JS（漏 setData、toggle 冲突等） | ⛔ 必须从 templates/interaction-components.html 照抄 JS |
| 飞书链接打不开 | URL 被加粗 | 裸发 URL，不加 `**` |
| noVNC WebSocket 断 | websockify 挂了 | `ssh root@… "docker exec -d daqiezi-hermes websockify 0.0.0.0:6080 localhost:5901"` |
| `patch` 替换占位符报 "Found 2 matches" | `{{TITLE}}` 在模板中出现多次 | 用 `replace_all=true` 或 `terminal` + Python `replace()` |
| 用 execute_code 的 read_file 处理 HTML 导致行号污染 | execute_code 版 read_file 带行号前缀 | 用 `write_file` 直接写，或 `terminal` + `sed` |
