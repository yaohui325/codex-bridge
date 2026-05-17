#!/usr/bin/env bash
# codex-bridge install.sh — 一键安装 + 依赖检查 + 部署软链
#
# 用法（在 clone 出的 codex-bridge/ 根目录跑）：
#   ./install.sh
#
# 退出码：
#   0 成功
#   1 依赖缺失或路径冲突
#   2 用户取消覆盖现有软链

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="codex-bridge"
SKILL_TARGET="$HOME/.claude/skills/$SKILL_NAME"

echo "=== codex-bridge install ==="
echo "  源目录: $SCRIPT_DIR"
echo "  目标:   $SKILL_TARGET"
echo ""

# ─────────────────────────────────────────────
echo "## 1. 检查依赖"
# ─────────────────────────────────────────────

FAILED=0

# bash 4+
if [ -n "${BASH_VERSION:-}" ]; then
  MAJOR=$(echo "$BASH_VERSION" | cut -d. -f1)
  if [ "$MAJOR" -ge 4 ]; then
    echo "  ✓ bash $BASH_VERSION"
  else
    echo "  ✗ bash $BASH_VERSION (需要 4+)"
    FAILED=$((FAILED + 1))
  fi
else
  echo "  ⚠ 当前不是 bash 环境（可能是 zsh），无法直接验证 bash 版本"
  echo "    macOS 默认 bash 是 3.2（太老），请用 brew install bash"
fi

# jq
if command -v jq >/dev/null 2>&1; then
  echo "  ✓ jq $(jq --version)"
else
  echo "  ✗ jq 未安装（macOS: brew install jq / linux: apt install jq）"
  FAILED=$((FAILED + 1))
fi

# codex CLI
if command -v codex >/dev/null 2>&1; then
  echo "  ✓ codex CLI: $(command -v codex)"
else
  echo "  ✗ codex CLI 未安装（参考 codex 官方文档安装）"
  FAILED=$((FAILED + 1))
fi

if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "ERROR: $FAILED 个依赖缺失，请先安装后重试" >&2
  exit 1
fi

# ─────────────────────────────────────────────
echo ""
echo "## 2. 部署 skill 到 ~/.claude/skills/"
# ─────────────────────────────────────────────

mkdir -p "$HOME/.claude/skills"

if [ -L "$SKILL_TARGET" ]; then
  EXISTING=$(readlink "$SKILL_TARGET")
  if [ "$EXISTING" = "$SCRIPT_DIR" ]; then
    echo "  ✓ 软链已存在且指向当前目录（无需重建）"
  else
    echo "  ⚠ 软链已存在但指向其他位置: $EXISTING"
    printf "  覆盖? (y/N) "
    read ANSWER
    if [ "${ANSWER}" = "y" ] || [ "${ANSWER}" = "Y" ]; then
      rm "$SKILL_TARGET"
      ln -s "$SCRIPT_DIR" "$SKILL_TARGET"
      echo "  ✓ 已覆盖: $SKILL_TARGET → $SCRIPT_DIR"
    else
      echo "  跳过（用户取消）"
      exit 2
    fi
  fi
elif [ -e "$SKILL_TARGET" ]; then
  echo "  ✗ $SKILL_TARGET 已存在且不是软链——不覆盖，请手动处理" >&2
  exit 1
else
  ln -s "$SCRIPT_DIR" "$SKILL_TARGET"
  echo "  ✓ 软链已创建: $SKILL_TARGET → $SCRIPT_DIR"
fi

# ─────────────────────────────────────────────
echo ""
echo "## 3. scripts/ 可执行权限"
# ─────────────────────────────────────────────

chmod +x "$SCRIPT_DIR/scripts/"*.sh
echo "  ✓ scripts/*.sh chmod +x"

# ─────────────────────────────────────────────
echo ""
echo "## 4. 验证"
# ─────────────────────────────────────────────

if [ -f "$SKILL_TARGET/SKILL.md" ]; then
  echo "  ✓ 可通过软链访问 SKILL.md"
else
  echo "  ✗ 软链无法访问 SKILL.md" >&2
  FAILED=$((FAILED + 1))
fi

if "$SKILL_TARGET/scripts/validate-bundle.sh" 2>&1 | grep -q "Usage:"; then
  echo "  ✓ scripts/validate-bundle.sh 可执行"
else
  echo "  ✗ scripts/validate-bundle.sh 不可执行或行为异常" >&2
  FAILED=$((FAILED + 1))
fi

if "$SKILL_TARGET/scripts/create-bundle.sh" 2>&1 | grep -q "Usage:"; then
  echo "  ✓ scripts/create-bundle.sh 可执行"
else
  echo "  ✗ scripts/create-bundle.sh 不可执行或行为异常" >&2
  FAILED=$((FAILED + 1))
fi

# ─────────────────────────────────────────────
echo ""
# ─────────────────────────────────────────────

if [ "$FAILED" -gt 0 ]; then
  echo "=== 安装完成但有 $FAILED 处验证未通过 ⚠ ==="
  exit 1
fi

echo "=== 安装完成 ✓ ==="
echo ""
echo "下一步："
echo "  1. 在任意 Claude Code 对话里说 '让 Codex 审一下这个 plan' 触发 skill"
echo "  2. 或显式 /codex-bridge"
echo ""
echo "卸载："
echo "  rm $SKILL_TARGET"
