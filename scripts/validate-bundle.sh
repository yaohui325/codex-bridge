#!/usr/bin/env bash
# validate-bundle.sh — 验证一个 bundle 目录的完整性，机械检查。
#
# 用法:
#   validate-bundle.sh <bundle-dir>
#
# 检查项:
#   - 必需文件存在
#   - JSON 合法性
#   - manifest 必需字段
#   - request.md 不含残留 {{VAR}} 占位符
#   - files/ 非空
#   - 语义检查（scenario / round / previous_rounds / max_rounds + purpose / schema title 匹配）
#   - response.json 完整校验（合法 + required + 类型 + key_findings.type enum + plan-review 4 维 + codify files_changed 子字段）
#
# 退出码:
#   0 全部通过
#   1 参数错误
#   2 检查未通过

set -uo pipefail

BUNDLE="${1:-}"
if [ -z "$BUNDLE" ]; then
  echo "Usage: $0 <bundle-dir>" >&2
  exit 1
fi
if [ ! -d "$BUNDLE" ]; then
  echo "ERROR: 目录不存在: $BUNDLE" >&2
  exit 1
fi
BUNDLE="$(cd "$BUNDLE" && pwd)"

FAILED=0

# check 函数：接收 argv 而非字符串（不用 eval，避免路径含特殊字符破坏命令解析）
check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  ✓ $desc"
  else
    echo "  ✗ $desc"
    FAILED=$((FAILED + 1))
  fi
}

echo "Validating: $BUNDLE"
echo ""

echo "## 文件存在性"
check "manifest.json 存在"        test -f "$BUNDLE/manifest.json"
check "request.md 存在"           test -f "$BUNDLE/request.md"
check "conversation.md 存在"      test -f "$BUNDLE/conversation.md"
check "response.schema.json 存在" test -f "$BUNDLE/response.schema.json"
check "files/ 目录存在"           test -d "$BUNDLE/files"

echo ""
echo "## JSON 合法性"
check "manifest.json 是合法 JSON"        jq empty "$BUNDLE/manifest.json"
check "response.schema.json 是合法 JSON" jq empty "$BUNDLE/response.schema.json"

echo ""
echo "## manifest 必需字段"
for field in round scenario status created_at bundle_dir; do
  check "manifest.$field 存在" jq -e "has(\"$field\")" "$BUNDLE/manifest.json"
done

echo ""
echo "## request.md 模板填充"
unfilled=0
if [ -f "$BUNDLE/request.md" ]; then
  unfilled=$(grep -o '{{[A-Z_][A-Z_0-9]*}}' "$BUNDLE/request.md" 2>/dev/null | wc -l | tr -d ' ')
fi
if [ "${unfilled:-0}" -eq 0 ]; then
  echo "  ✓ request.md 无残留 {{VAR}} 占位符"
else
  echo "  ✗ request.md 还有 $unfilled 处未填充的 {{VAR}}："
  grep -o '{{[A-Z_][A-Z_0-9]*}}' "$BUNDLE/request.md" | sort -u | sed 's/^/      /'
  FAILED=$((FAILED + 1))
fi

echo ""
echo "## files/ 非空"
file_count=0
if [ -d "$BUNDLE/files" ]; then
  file_count=$(find "$BUNDLE/files" -type f 2>/dev/null | wc -l | tr -d ' ')
fi
if [ "$file_count" -gt 0 ]; then
  echo "  ✓ files/ 含 $file_count 个文件"
else
  echo "  ✗ files/ 为空"
  FAILED=$((FAILED + 1))
fi

echo ""
echo "## 语义检查"
SCENARIO=$(jq -r '.scenario // empty' "$BUNDLE/manifest.json" 2>/dev/null)
ROUND=$(jq -r '.round // 0' "$BUNDLE/manifest.json" 2>/dev/null)
MAX_ROUNDS=$(jq -r '.max_rounds // 1' "$BUNDLE/manifest.json" 2>/dev/null)
PREV_ROUNDS_COUNT=$(jq -r '.previous_rounds | length' "$BUNDLE/manifest.json" 2>/dev/null || echo 0)
PURPOSE=$(jq -r '.purpose // empty' "$BUNDLE/manifest.json" 2>/dev/null)
SCHEMA_TITLE=$(jq -r '.title // empty' "$BUNDLE/response.schema.json" 2>/dev/null)

# scenario 合法值
case "$SCENARIO" in
  plan-review|codify|review-iteration|verification-round)
    echo "  ✓ scenario 合法: $SCENARIO" ;;
  *)
    echo "  ✗ scenario 不在合法集合内: '$SCENARIO'"
    FAILED=$((FAILED + 1)) ;;
esac

# round 正整数
if [[ "$ROUND" =~ ^[1-9][0-9]*$ ]]; then
  echo "  ✓ round 是正整数: $ROUND"
else
  echo "  ✗ round 不是正整数: '$ROUND'"
  FAILED=$((FAILED + 1))
fi

# Round > 1 时 previous_rounds 必须非空
if [ "${ROUND}" -gt 1 ] 2>/dev/null; then
  if [ "${PREV_ROUNDS_COUNT}" -gt 0 ]; then
    echo "  ✓ Round > 1 且 previous_rounds 非空 (${PREV_ROUNDS_COUNT} 项)"
  else
    echo "  ✗ Round=${ROUND} 但 previous_rounds 为空"
    FAILED=$((FAILED + 1))
  fi
fi

# Round > max_rounds 必须 purpose + scenario ∈ {plan-review, verification-round}
# (v1.1: 扩展豁免到 verification-round；避免 codify/review-iteration 通过 purpose 绕过 2 轮硬上限)
if [ "${ROUND}" -gt "${MAX_ROUNDS}" ] 2>/dev/null; then
  if [ -n "${PURPOSE}" ] && { [ "${SCENARIO}" = "plan-review" ] || [ "${SCENARIO}" = "verification-round" ]; }; then
    echo "  ⚠ Round=${ROUND} > max_rounds=${MAX_ROUNDS}，${SCENARIO} 审计/验证 round 例外（purpose: ${PURPOSE}）"
  elif [ -n "${PURPOSE}" ]; then
    echo "  ✗ Round=${ROUND} > max_rounds=${MAX_ROUNDS} 但 scenario=${SCENARIO}（purpose 豁免仅对 plan-review / verification-round 生效，业务迭代不允许超 max_rounds）"
    FAILED=$((FAILED + 1))
  else
    echo "  ✗ Round=${ROUND} > max_rounds=${MAX_ROUNDS} 且无 purpose 字段"
    FAILED=$((FAILED + 1))
  fi
fi

# schema title 与 scenario 必须匹配（warn → fail）
if [ -n "$SCHEMA_TITLE" ] && [ -n "$SCENARIO" ]; then
  if echo "$SCHEMA_TITLE" | grep -q "$SCENARIO"; then
    echo "  ✓ schema title 含 scenario 名"
  else
    echo "  ✗ schema title '$SCHEMA_TITLE' 不含 scenario '$SCENARIO'（场景错配）"
    FAILED=$((FAILED + 1))
  fi
fi

echo ""
echo "## verification-round 专用检查 (v1.2)"

# v1.2 F10: verification-round 的 previous_rounds 必须恰好 1 项（防"一个验证轮验证多个主轮"误用）
if [ "${SCENARIO}" = "verification-round" ]; then
  if [ "${PREV_ROUNDS_COUNT}" -eq 1 ] 2>/dev/null; then
    echo "  ✓ verification-round previous_rounds 恰好 1 项"
  else
    echo "  ✗ verification-round previous_rounds 必须恰好 1 项（当前 ${PREV_ROUNDS_COUNT}）"
    FAILED=$((FAILED + 1))
  fi
fi

# v1.2 F11: verification-round 防递归 + purpose round-N 与 previous manifest.round 绑定校验
PURPOSE_ROUND=""
if [ "${SCENARIO}" = "verification-round" ] && [ "${PREV_ROUNDS_COUNT}" -eq 1 ] 2>/dev/null; then
  PREV_BUNDLE=$(jq -r '.previous_rounds[0]' "$BUNDLE/manifest.json" 2>/dev/null)
  PREV_MANIFEST="${PREV_BUNDLE}/manifest.json"
  PURPOSE_ROUND=$(echo "${PURPOSE}" | grep -oE 'round-[0-9]+' | head -1 | sed 's/round-//')
  if [ -f "${PREV_MANIFEST}" ]; then
    PREV_SCENARIO=$(jq -r '.scenario // empty' "${PREV_MANIFEST}" 2>/dev/null)
    PREV_ROUND_VAL=$(jq -r '.round // 0' "${PREV_MANIFEST}" 2>/dev/null)
    if [ "${PREV_SCENARIO}" = "verification-round" ]; then
      echo "  ✗ 防递归: previous round 是 verification-round，不允许 (路径: ${PREV_BUNDLE})"
      FAILED=$((FAILED + 1))
    else
      echo "  ✓ 防递归: previous round scenario = ${PREV_SCENARIO}"
    fi
    if [ -n "${PURPOSE_ROUND}" ] && [ "${PURPOSE_ROUND}" = "${PREV_ROUND_VAL}" ]; then
      echo "  ✓ purpose round-${PURPOSE_ROUND} 与 previous manifest.round 一致"
    elif [ -n "${PURPOSE_ROUND}" ]; then
      echo "  ✗ purpose round-${PURPOSE_ROUND} 与 previous manifest.round (${PREV_ROUND_VAL}) 不一致"
      FAILED=$((FAILED + 1))
    fi
  else
    echo "  ⚠ previous bundle manifest 不可读 (${PREV_MANIFEST})，无法验证防递归 + round 绑定（保守降级，不 fail）"
  fi
fi

# v1.2 F12: verification-round 的 purpose 必须匹配 '^verify round-[0-9]+ extrapolations$'
if [ "${SCENARIO}" = "verification-round" ]; then
  if echo "${PURPOSE}" | grep -qE '^verify round-[0-9]+ extrapolations$'; then
    echo "  ✓ purpose 格式正确"
  else
    echo "  ✗ verification-round purpose 必须匹配 '^verify round-[0-9]+ extrapolations\$'，当前: '${PURPOSE}'"
    FAILED=$((FAILED + 1))
  fi
fi

# v1.2 F13: verification-round files/ 必含 extracted-patterns.md + round-N-response.json
if [ "${SCENARIO}" = "verification-round" ]; then
  if [ -f "$BUNDLE/files/extracted-patterns.md" ]; then
    echo "  ✓ files/extracted-patterns.md 存在"
  else
    echo "  ✗ verification-round files/ 缺 extracted-patterns.md (v1.1 流程要求 inline 主轮 extracted-patterns)"
    FAILED=$((FAILED + 1))
  fi
  if [ -n "${PURPOSE_ROUND}" ]; then
    EXPECTED_RESP="$BUNDLE/files/round-${PURPOSE_ROUND}-response.json"
    if [ -f "${EXPECTED_RESP}" ]; then
      echo "  ✓ files/round-${PURPOSE_ROUND}-response.json 存在"
    else
      echo "  ✗ verification-round files/ 缺 round-${PURPOSE_ROUND}-response.json (v1.1 流程要求 inline 主轮 response)"
      FAILED=$((FAILED + 1))
    fi
  fi
fi

# 如果 response.json 已生成，做完整校验（复用 SKILL.md step 10 的逻辑）
if [ -f "$BUNDLE/response.json" ]; then
  echo ""
  echo "## response.json 完整校验"

  check "response.json 是合法 JSON" jq empty "$BUNDLE/response.json"

  # v1.2 F9: 主场景应有 extracted-patterns.md（warn——因为 11.5 是判断式，"无 pattern" 也是合法状态）
  if [ "$SCENARIO" != "verification-round" ]; then
    if [ -f "$BUNDLE/extracted-patterns.md" ]; then
      echo "  ✓ extracted-patterns.md 存在（v1.1 pattern extraction 已执行）"
    else
      echo "  ⚠ extracted-patterns.md 缺失 — 主轮 codex 跑完后应执行 SKILL.md step 11.5（即使全部 finding 判'无 pattern'也需写文件说明）"
    fi
  fi

  if [ "$SCENARIO" = "verification-round" ]; then
    # verification-round 用独立 schema（focused verification，字段不同）
    for field in task_understanding verifications additional_findings summary; do
      check "response.$field 存在" jq -e "has(\"$field\")" "$BUNDLE/response.json"
    done
    check "顶层字段类型正确" jq -e '(.task_understanding | type == "string") and (.verifications | type == "array") and (.additional_findings | type == "array") and (.summary | type == "string")' "$BUNDLE/response.json"
    check "verifications[].verdict 全在 enum 内" jq -e '[.verifications[].verdict] | all(. == "confirmed" or . == "refuted" or . == "partial" or . == "unsure")' "$BUNDLE/response.json"
    check "verifications[].candidate_id 是 string" jq -e '[.verifications[].candidate_id] | all(type == "string")' "$BUNDLE/response.json"
    check "verifications[].reasoning 是 string" jq -e '[.verifications[].reasoning] | all(type == "string")' "$BUNDLE/response.json"
  else
    # plan-review / codify / review-iteration 标准 schema
    for field in task_understanding result key_findings specific_suggestions open_questions uncertainty; do
      check "response.$field 存在" jq -e "has(\"$field\")" "$BUNDLE/response.json"
    done

    # 字段类型
    check "顶层字段类型正确" jq -e '(.task_understanding | type == "string") and (.result | type == "string") and (.key_findings | type == "array") and (.specific_suggestions | type == "array") and (.open_questions | type == "array") and (.uncertainty | type == "string")' "$BUNDLE/response.json"

    # key_findings.type enum
    check "key_findings[].type 全在 enum 内" jq -e '[.key_findings[].type] | all(. == "hidden_assumption" or . == "disagreement" or . == "risk" or . == "validation")' "$BUNDLE/response.json"

    # plan-review: dimension enum + 4 维覆盖
    if [ "$SCENARIO" = "plan-review" ]; then
      check "key_findings[].dimension 全在 4 维 enum 内" jq -e '[.key_findings[].dimension] | all(. == "rationality" or . == "hidden_assumptions" or . == "conventions" or . == "scope_control")' "$BUNDLE/response.json"
      DIM_COUNT=$(jq -r '[.key_findings[].dimension] | unique | length' "$BUNDLE/response.json" 2>/dev/null || echo 0)
      if [ "${DIM_COUNT:-0}" -ge 4 ]; then
        echo "  ✓ 4 维度全覆盖 (${DIM_COUNT} 个 unique dimension)"
      else
        echo "  ⚠ 只覆盖 ${DIM_COUNT} / 4 维度（plan-review 期望全覆盖，但视为审阅不充分而非脚本 fail）"
      fi
    fi

    # codify / review-iteration: files_changed 子字段
    if [ "$SCENARIO" = "codify" ] || [ "$SCENARIO" = "review-iteration" ]; then
      check "files_changed 存在" jq -e 'has("files_changed")' "$BUNDLE/response.json"
      check "files_changed 子字段（created/modified/deleted）都是数组" jq -e '(.files_changed.created | type == "array") and (.files_changed.modified | type == "array") and (.files_changed.deleted | type == "array")' "$BUNDLE/response.json"
    fi
  fi
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
  echo "全部通过 ✓"
  exit 0
else
  echo "$FAILED 处不通过 ✗" >&2
  exit 2
fi
