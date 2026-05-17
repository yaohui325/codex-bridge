# verification-round 场景说明（skill 维护者参考）

让 Codex 验证 Claude Code 从主轮 finding 中提取的 patterns + 横向查证出的 candidates。**Focused verification，非完整 plan-review**。

## 触发条件

仅在 SKILL.md step 11.6 中触发：主轮 finding → Claude Code pattern extraction → 横向查证 → 有 candidates → 创建 verification-round bundle。

**不**由用户自然语言触发（用户说"让 Codex 验证"通常是想要 review-iteration 或 plan-review）。

## 模板变量

| 变量 | 含义 |
|---|---|
| `{{ROUND}}` | 验证轮自己的 round 号（一般是主轮 round + 1） |
| `{{MAIN_ROUND}}` | 被验证的主轮 round 号 |
| `{{MAIN_ROUND_BUNDLE}}` | 主轮 bundle 绝对路径 |
| `{{BUNDLE_ABSOLUTE_PATH}}` | 本验证轮 bundle 绝对路径 |
| `{{PROJECT_ROOT}}` | 项目根路径 |
| `{{TIMESTAMP}}` | ISO-8601 |
| `{{MAIN_ROUND_FINDINGS_SUMMARY}}` | 主轮 finding 的精炼摘要（5-10 条，按 type 分组） |
| `{{EXTRACTED_PATTERNS_SUMMARY}}` | extracted-patterns.md 里的 Pattern P1/P2 摘要 |
| `{{CANDIDATES_SUMMARY}}` | 外推的 X1/X2/Y1 列表（含理由） |

## 调用命令（同 plan-review）

```bash
codex exec \
  --cd "<PROJECT_ROOT>" \
  --sandbox read-only \
  --skip-git-repo-check \
  -o "<BUNDLE>/response.json" \
  < "<BUNDLE>/request.md"
```

`<BUNDLE>` = `<PROJECT_ROOT>/.codex-bridge/round-<N+1>`

**注意**：
- **不传** `--output-schema`（codexapi 代理 502，已成既定事实）
- 用 stdin (`<`)
- sandbox = `read-only`（验证轮不应改文件）

## manifest.json 必填字段（与其他 scenario 不同的关键）

```json
{
  "round": <N+1>,
  "max_rounds": 1,
  "scenario": "verification-round",
  "purpose": "verify round-<N> extrapolations",
  "previous_rounds": ["<absolute path to round-N>"],
  "status": "...",
  ...
}
```

**`purpose` 字段是 hard requirement**——`validate-bundle.sh` 会用 `purpose` 字段对 `verification-round` 豁免 `round > max_rounds` 检查。如不填，验证轮会因 `round > max_rounds` 被拦截。

## 跑完后 Claude Code 要做什么

1. 读 `response.json`
2. 跑 **7 步 jq 校验**（不是 8 步——verification schema 字段不同）：
   - a) JSON 合法
   - b) required 字段（`task_understanding` / `verifications` / `additional_findings` / `summary`）
   - c) 顶层字段类型
   - d) `verifications[].verdict` 全在 enum 内
   - e) `verifications[].candidate_id` 是 string
   - f) `verifications[].reasoning` 是 string
   - g) 任一失败 → 报错保留 bundle

3. 渲染 `response.md`（人话版，见下方模板）
4. **综合主轮 finding + 验证轮 verdicts** 更新 v2 plan / 代码：
   - `confirmed` candidates → 加进 v2 修正清单
   - `refuted` candidates → 不动（但在 v2 备注"经 verification 判 refuted"）
   - `partial` candidates → 决策（参考 Claude Code 自己的 reasoning）
   - `unsure` candidates → 补充信息后人工判断（**不**再开二级验证轮，防递归）
   - `additional_findings` → 加进 v2 修正清单

5. 更新主轮 bundle 的 `extracted-patterns.md`，加"验证结果"段

## response.md 渲染模板

```markdown
# Codex 验证结果（verification-round Round N+1）

## Codex 的任务理解
{response.task_understanding}

## 整体总结
{response.summary}

## 每个 candidate 的判定

### ✓ Confirmed (N 条)
- X1: {reasoning}
- ...

### ✗ Refuted (N 条)
- X2: {reasoning}
- ...

### ⚠ Partial (N 条)
- Y1: {reasoning}
- ...

### ❓ Unsure (N 条)
- Y2: {reasoning}（需要补充：xxx）
- ...

## Codex 新发现的同类问题（additional_findings）
- ...

---

## 综合更新（Claude Code）

基于主轮 + 验证轮的 v2 修正清单：
- 来自主轮的：...
- confirmed 来自外推：...
- additional_findings 来自验证：...
- 经验证 refuted（不修）：...
```

## 失败处理

- response.json 不存在 → "codex exec 可能 502 重试；或主流程降级用主轮 findings 继续"
- response.json schema 不符 → Claude Code 报错保留 bundle，让用户决定重跑或人工降级
- 全部 refuted → 接受，意味着 Claude Code 的外推不准；标 extracted-patterns.md 为"过度泛化警告"
- 全部 unsure → 信息不够，提示用户补充信息后重新做 pattern extraction
- 验证轮自身的 codex exec 完全失败 → 见 SKILL.md 失败处理，**不**阻断主流程

## 不要做的事

- ❌ **不要**把验证轮当 review-iteration 用（不能让 Codex 改文件，sandbox 强制 read-only）
- ❌ **不要**对验证轮的 additional_findings 再开二级验证轮（防递归，硬约束）
- ❌ **不要**用 verification-round 替代主流程 plan-review（用途不同）
