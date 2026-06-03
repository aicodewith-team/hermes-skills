#!/bin/bash
# validate-html.sh — Hermes HTML 发布前样式合规检查
# Usage: bash validate-html.sh /opt/data/www/page.html

set -euo pipefail

PAGE="${1:-}"
if [ -z "$PAGE" ]; then
  echo "Usage: validate-html.sh <path-to-html>"
  exit 1
fi
if [ ! -f "$PAGE" ]; then
  echo "❌ 文件不存在: $PAGE"
  exit 1
fi

ERRORS=0
WARNINGS=0

echo "═══ 检查: $(basename "$PAGE") ═══"

# 1. 必须引用 theme.css
if grep -q 'theme.css' "$PAGE"; then
  echo "  ✅ theme.css 引用"
else
  echo "  ❌ 缺少 theme.css 引用 — 必须加 <link rel=\"stylesheet\" href=\"/theme.css\">"
  ERRORS=$((ERRORS + 1))
fi

# 2. 必须使用 <main class="container">
if grep -q '<main class="container"' "$PAGE"; then
  echo "  ✅ 标准容器 <main class=\"container\">"
else
  echo "  ❌ 缺少标准容器结构 — 必须用 <main class=\"container\">"
  ERRORS=$((ERRORS + 1))
fi

# 3. 禁止内联 max-width 覆盖
if grep -q 'style="max-width' "$PAGE" 2>/dev/null; then
  echo "  ⚠️ 检测到内联 max-width — 会覆写 .container 宽度，改用标准容器"
  WARNINGS=$((WARNINGS + 1))
fi

# 4. 禁止暗色背景
if grep -qiE 'background[^;]*#[0-3][0-9a-f]{5}' "$PAGE" 2>/dev/null; then
  echo "  ⚠️ 检测到暗色背景 — hermes-daqiezi 必须用亮色主题（theme.css 白底）"
  WARNINGS=$((WARNINGS + 1))
fi

# 5. 禁止自建 :root { } 变量块（会覆盖 theme.css）
#    只匹配 CSS 规则块 :root { ... }，不抓注释中的文字
if grep -n ':root\s*{' "$PAGE" 2>/dev/null | grep -v '<!--' | grep -q .; then
  echo "  ⚠️ 检测到自建 :root 变量 — 可能与 theme.css 冲突，页面色调不一致"
  WARNINGS=$((WARNINGS + 1))
else
  echo "  ✅ 无自建 :root 变量"
fi

# 6. 检查 meta charset
if grep -q '<meta charset="utf-8"' "$PAGE"; then
  echo "  ✅ UTF-8 声明"
else
  echo "  ⚠️ 缺少 charset 声明"
  WARNINGS=$((WARNINGS + 1))
fi

# 7. 检查 viewport
if grep -q 'viewport' "$PAGE"; then
  echo "  ✅ viewport 声明"
else
  echo "  ⚠️ 缺少 viewport 声明 — 手机端可能无法正常缩放"
  WARNINGS=$((WARNINGS + 1))
fi

echo ""
if [ "$ERRORS" -gt 0 ]; then
  echo "❌ 阻断发布: $ERRORS 项错误 (ERRORS=$ERRORS, WARNINGS=$WARNINGS)"
  exit 1
elif [ "$WARNINGS" -gt 0 ]; then
  echo "✅ 通过（$WARNINGS 项警告，建议修复后发布）"
  exit 0
else
  echo "✅ 全部通过"
  exit 0
fi
