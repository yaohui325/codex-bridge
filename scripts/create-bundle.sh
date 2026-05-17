#!/usr/bin/env bash
# create-bundle.sh — 为 codex-bridge skill 创建一个新 round 的 bundle 骨架。
#
# 用法:
#   create-bundle.sh <scenario> [<project-root>] [<round-number>]
#
# 参数:
#   scenario:      plan-review | codify | review-iteration | verification-round
#   project-root:  默认当前目录
#   round-number:  默认自动检测（已有最大 round + 1）
#
# 输出:
#   stdout: bundle 目录的绝对路径（供 Claude Code 后续 Write）
#   stderr: 创建过程的人话日志
#
# 退出码:
#   0 成功
#   1 参数错误
#   2 scenario 无效
#   3 已存在的 round 目录（避免覆盖）
#   4 找不到 skill 文件

set -euo pipefail

SCENARIO="${1:-}"
if [ -z "$SCENARIO" ]; then
  echo "Usage: $0 <scenario> [project-root] [round-number]" >&2
  echo "  scenario: plan-review | codify | review-iteration | verification-round" >&2
  exit 1
fi

PROJECT_ROOT="${2:-$(pwd)}"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

case "$SCENARIO" in
  plan-review|codify|review-iteration|verification-round) ;;
  *)
    echo "ERROR: scenario 必须是 plan-review / codify / review-iteration / verification-round（当前: $SCENARIO）" >&2
    exit 2
    ;;
esac

# 找 skill 根目录（脚本所在目录的父目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(dirname "$SCRIPT_DIR")"
if [ ! -f "$SKILL_ROOT/SKILL.md" ]; then
  # fallback: 尝试常见位置
  for cand in \
    "$HOME/.claude/skills/codex-bridge" \
    "$PROJECT_ROOT/codex-bridge" ; do
    if [ -f "$cand/SKILL.md" ]; then
      SKILL_ROOT="$cand"
      break
    fi
  done
fi
if [ ! -f "$SKILL_ROOT/SKILL.md" ]; then
  echo "ERROR: 找不到 codex-bridge skill 根目录（脚本父目录、~/.claude/skills/codex-bridge 都没找到 SKILL.md）" >&2
  exit 4
fi

# 检测 round number
if [ -n "${3:-}" ]; then
  ROUND="$3"
else
  ROUND=1
  while [ -d "$PROJECT_ROOT/.codex-bridge/round-$ROUND" ]; do
    ROUND=$((ROUND + 1))
  done
fi

# 校验 ROUND 是正整数（必须在创建任何目录/文件之前，避免半成品 bundle artifact）
if ! [[ "$ROUND" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: round 必须是正整数（当前: '$ROUND'）" >&2
  exit 1
fi

BUNDLE="$PROJECT_ROOT/.codex-bridge/round-$ROUND"
if [ -d "$BUNDLE" ]; then
  echo "ERROR: bundle 目录已存在: $BUNDLE" >&2
  echo "  请手动删除或指定不同 round-number" >&2
  exit 3
fi

mkdir -p "$BUNDLE/files"

# 复制 schema
cp "$SKILL_ROOT/templates/$SCENARIO/response.schema.json" "$BUNDLE/response.schema.json"

# 写空白 manifest，用 jq -n 确保 JSON 转义正确（避免 heredoc 在路径含特殊字符时生成非法 JSON）
TS="$(date +"%Y-%m-%dT%H:%M:%S%z")"
MAX_ROUNDS=1
[ "$SCENARIO" = "review-iteration" ] && MAX_ROUNDS=2

jq -n \
  --argjson round "$ROUND" \
  --argjson max_rounds "$MAX_ROUNDS" \
  --arg scenario "$SCENARIO" \
  --arg created_at "$TS" \
  --arg bundle_dir "$BUNDLE" \
  '{
    round: $round,
    max_rounds: $max_rounds,
    scenario: $scenario,
    status: "pending",
    claude_session_jsonl: null,
    previous_rounds: [],
    created_at: $created_at,
    bundle_dir: $bundle_dir,
    codex_command: null,
    codex_exit_code: null
  }' > "$BUNDLE/manifest.json"

# 复制 request.md 模板（待 Claude Code 填 {{VAR}}）
cp "$SKILL_ROOT/templates/$SCENARIO/request.md" "$BUNDLE/request.md"

echo "✓ Bundle 骨架已创建" >&2
echo "  scenario: $SCENARIO" >&2
echo "  round:    $ROUND" >&2
echo "  bundle:   $BUNDLE" >&2
echo "" >&2
echo "TODO（Claude Code 接管）：" >&2
echo "  1. 填 $BUNDLE/request.md 里所有 {{VAR}} 占位符" >&2
echo "  2. 拷贝 plan + 相关文件到 $BUNDLE/files/" >&2
echo "  3. 写 $BUNDLE/conversation.md（蒸馏 + JSONL 路径）" >&2
echo "  4. 更新 manifest.json 的 claude_session_jsonl 字段" >&2
echo "  5. 跑 $SKILL_ROOT/scripts/validate-bundle.sh \"$BUNDLE\" 验证完整性" >&2
echo "  6. 调 codex exec（见 templates/$SCENARIO/prompt-notes.md）" >&2

# stdout: 只输出 bundle 路径，方便 Claude Code 用 $(...) 捕获
echo "$BUNDLE"
