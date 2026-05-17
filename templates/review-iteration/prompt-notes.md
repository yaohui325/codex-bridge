# review-iteration 场景说明（skill 维护者参考）

Round 2，让 Codex 基于 Claude review 改 Round 1 的代码。**硬上限：不允许 Round 3**。

## 模板变量

通用变量见 `plan-review/prompt-notes.md`。本场景特有：

| 变量 | 含义 |
|---|---|
| `{{ROUND_1_BUNDLE_PATH}}` | round-1 的绝对路径 |
| `{{ROUND_1_REQUEST_FULL}}` | round-1/request.md 完整内容 |
| `{{ROUND_1_RESPONSE_FULL}}` | round-1/response.json 完整内容 |
| `{{CLAUDE_REVIEW_FULL}}` | round-1/claude-review.md 完整内容 |

注意：`{{FILES_INLINE_BLOCK}}` 应该是 **Round 1 改完之后的最新文件状态**（不是 Round 1 开始前的版本）。

## 调用命令

```bash
codex exec \
  --cd "<PROJECT_ROOT>" \
  --sandbox workspace-write \
  --skip-git-repo-check \
  -o "<BUNDLE>/response.json" \
  < "<BUNDLE>/request.md"
```

`<BUNDLE>` = `<PROJECT_ROOT>/.codex-bridge/round-2`

**注意**：
- **不传** `--output-schema`（codexapi 代理 502）
- 用 stdin (`<`)，schema 通过 prompt 里 `./response.schema.json` 引用让 Codex 遵循
- `files_changed` 校验同 codify 场景（git → mtime 快照 → 明示无法自动校验）

## 跑完后 Claude Code 要做什么

1. 读 `response.json`
2. 渲染 `response.md`
3. `git status` / `git diff` 验证 Round 2 新增改动
3a. **v1.1 Pattern Extraction**（v1.2 新增必走，即使终轮也走，按 SKILL.md F0 隐式触发）：
   - 对每条 accepted finding 走 step 11.5/11.6——写 `<bundle>/extracted-patterns.md`
   - 横向查证 → 如有 candidates → 触发 verification-round（注意：review-iteration 是 Round 2 终轮，但 verification-round 用 manifest.purpose 字段豁免，**不算**违反 2 轮硬上限）
4. **强制结束**——不允许触发 Round 3
5. 把 `round-2/manifest.json` 的 `status` 设为 `completed`
6. 如果 Round 2 仍然不满意 → 报告给用户、保留 bundle、**让用户决定**（手动开新 round-1 / 放弃）

## response.md 渲染模板

```markdown
# Codex 修改结果（review-iteration Round 2 — 终轮）

## 任务理解
{response.task_understanding}

## 做了什么
{response.result}

## 改动文件（本轮新增的改动）
- Created: {files_changed.created.join(", ") or "无"}
- Modified: {files_changed.modified.join(", ") or "无"}
- Deleted: {files_changed.deleted.join(", ") or "无"}

## 接受 / 拒绝的 Review 意见

### 接受并按 review 改了
{key_findings 里 type=validation 的项}

### 不同意 review、按自己理解改了
{key_findings 里 type=disagreement 的项}

## 新引入的风险
{key_findings 里 type=risk 的项}

## 后续可继续的建议
{specific_suggestions}

## 待拍板
{open_questions}

## 不确定
{uncertainty}

---
**注：这是终轮，不会再有 Round 3。如果仍有问题，请用户决定下一步。**
```

## 防止 Round 3 创建

跑完 Round 2 后，Claude Code **必须**：

1. 把 `round-2/manifest.json` 的 `status` 设为 `completed`
2. **不主动创建 `round-3/`**
3. 如果用户再要求"还要再来一轮"，Claude Code 应该说：
   > "review-iteration 硬上限 2 轮已用完。建议起一个全新的 round-1 codify（如果还要继续改），或者你直接接手改剩下的部分。"

## Round 2 vs Round 1 实现差异

- Round 1 = codify：从需求出发写代码
- Round 2 = review-iteration：基于 Round 1 + Claude review **微调**

**警告信号**：如果 Round 2 改动量 ≈ Round 1，可能 Codex 跑偏或 Claude review 过于激进。Claude Code 在渲染 response.md 时应额外提示用户检查。

## 失败处理

- `response.json` 不存在 / schema 校验失败：同其他场景，保留 bundle、报错
- `files_changed` 与 git diff 不一致：警告用户、不自动重试
- Codex 拒绝接受任何 review 意见（全部 disagreement）：警告，可能用户的 review 和 Codex 的设计哲学冲突，建议用户人工介入
