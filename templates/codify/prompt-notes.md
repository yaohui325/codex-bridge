# codify 场景说明（skill 维护者参考）

让 Codex 写代码完成具体任务。一般是 review-iteration 场景的前置（Round 1）。

## 模板变量

通用变量见 `plan-review/prompt-notes.md`。本场景特有：

| 变量 | 含义 |
|---|---|
| `{{CODING_TASK_DESCRIPTION}}` | Claude Code 用自然语言写的"要做什么"描述 |
| `{{DEFINITION_OF_DONE}}` | 完成标准列表（勾选式或自由文本） |

## 调用命令

```bash
codex exec \
  --cd "<PROJECT_ROOT>" \
  --sandbox workspace-write \
  --skip-git-repo-check \
  -o "<BUNDLE>/response.json" \
  < "<BUNDLE>/request.md"
```

**注意**：
- **sandbox 必须是 `workspace-write`**，read-only 下 Codex 没法改文件
- **不传** `--output-schema`（codexapi 代理 502）
- 用 stdin (`<`) 不用 `"$(cat ...)"`

## 跑完后 Claude Code 要做什么

1. 读 `response.json`
2. 渲染 `response.md`
3. **用 `git status` / `git diff` 实际验证 `files_changed` 字段真实**
4. 让用户看一眼：实际改动 + Codex 的 `result` + `open_questions`
4a. **v1.1 Pattern Extraction**（v1.2 新增必走，按 SKILL.md F0 隐式触发）：
   - 对每条 accepted finding（type ∈ risk/hidden_assumption/disagreement）走 step 11.5/11.6——写 `<bundle>/extracted-patterns.md`
   - 横向查证 → 如有 candidates → 触发 verification-round（见 [templates/verification-round/prompt-notes.md](../verification-round/prompt-notes.md)）
   - 综合主轮 + 验证轮 → 再做下面 step 5 决策

5. **决定是否需要 Round 2 review-iteration**：
   - Codex 做对了 → 完成，end
   - 有偏差但小 → Claude Code 写 `round-1/claude-review.md` → 触发 review-iteration
   - 完全跑偏 → 通知用户、保留 bundle、不自动重跑（避免烧钱）

## response.md 渲染模板

```markdown
# Codex 编码结果（codify Round {{ROUND}}）

## 任务理解
{response.task_understanding}

## 做了什么
{response.result}

## 改动文件
- Created: {files_changed.created.join(", ") or "无"}
- Modified: {files_changed.modified.join(", ") or "无"}
- Deleted: {files_changed.deleted.join(", ") or "无"}

## 关键发现
{遍历 key_findings 按 type 分组渲染}

## 后续建议
{specific_suggestions 列表}

## 待拍板
{open_questions}

## 不确定的点
{uncertainty}
```

## claude-review.md 模板（如果决定触发 Round 2）

Claude Code 写到 `round-1/claude-review.md`：

```markdown
# Claude Code 对 Codex Round 1 的 Review

## 整体评价
{满意 / 部分满意 / 不满意}

## 具体问题

### 问题 1: <一句话>
- 涉及文件: <path:line>
- 现状: <Codex 写的样子，inline 代码片段>
- 期望: <希望改成的样子>
- 理由: <为什么>

### 问题 2: ...

## 不需要改的（Codex 做对了的）
- ...

## Round 2 请求
{明确列出：希望 Codex 在 Round 2 做哪几件事，1/2/3/...}
```

## files_changed 校验（按可用工具降级）

跑完 codex exec 之后，Claude Code **必须**校验 `files_changed` 字段真实。按以下优先级降级：

### 1. 优先：git 校验

```bash
cd "<PROJECT_ROOT>" && git status --short
```

- git 看到的改动 ⊇ `files_changed` 声明的 → OK
- git 有未声明的改动 → 警告用户，Codex 漏报
- 声明的改动 git 没看到 → 警告用户，Codex 说做了但没做

### 2. 无 git 时：mtime 快照（greenfield / 临时项目）

调 codex **之前**生成基线快照——**用 `mktemp` 避免并发覆盖**：

```bash
SNAPSHOT_BEFORE=$(mktemp /tmp/codex-bridge-before.XXXXXX)
find "<PROJECT_ROOT>" -type f \
  -not -path '*/.codex-bridge/*' \
  -not -path '*/node_modules/*' \
  -not -path '*/.git/*' \
  -exec stat -f "%m %N" {} \; | sort > "$SNAPSHOT_BEFORE"
```

调完后再快照 + diff + 清理：

```bash
SNAPSHOT_AFTER=$(mktemp /tmp/codex-bridge-after.XXXXXX)
find "<PROJECT_ROOT>" -type f \
  -not -path '*/.codex-bridge/*' \
  -not -path '*/node_modules/*' \
  -not -path '*/.git/*' \
  -exec stat -f "%m %N" {} \; | sort > "$SNAPSHOT_AFTER"
diff "$SNAPSHOT_BEFORE" "$SNAPSHOT_AFTER"
rm -f "$SNAPSHOT_BEFORE" "$SNAPSHOT_AFTER"
```

- mtime 变化的文件 → 应在 `files_changed.modified`
- 新增的文件 → `files_changed.created`
- 消失的文件 → `files_changed.deleted`

> ⚠️ **mtime 边界限制**：`stat -f "%m %N"` 只有**秒级精度**。同一秒内的快速修改、保留 mtime 的工具、或内容变化但 mtime 未变的情况都可能漏报。仅作临时审计信号，不替代 git。

### 3. 两者都不可用：明示无法自动校验

在 `response.md` 渲染时加警告：

> ⚠️ 此项目无 git 且未做 mtime 快照基线，`files_changed` 无法自动校验。请人工 review 实际改动。

## 防误区

- 不要直接信 `files_changed`，一定要 git 验证
- Round 1 codify 跑完不要自动跑 Round 2，先让用户看
- 如果 codify 用了 `read-only` sandbox（误配置）：Codex 会报错，Claude Code 必须感知并报错重跑
