# plan-review 场景说明（skill 维护者参考）

本目录三件套用于"让 Codex 审一个 Claude Code 写的 plan"。

## 4 维度评估的初衷

| 维度 | 为什么重要 |
|---|---|
| **方案合理性** | 防止 plan 选错根本方向 |
| **隐藏假设** | 防止 plan 建立在"我以为"上 |
| **项目惯例** | 防止 plan 偏离既有架构/风格 |
| **范围控制** | 防止 plan 添加不必要的复杂度 |

## 模板变量映射

| 变量 | 来源 / 含义 |
|---|---|
| `{{ROUND}}` | 始终 `1`（plan-review 不迭代） |
| `{{BUNDLE_ABSOLUTE_PATH}}` | `<project>/.codex-bridge/round-1` |
| `{{PROJECT_ROOT}}` | 当前 cwd 绝对路径 |
| `{{TIMESTAMP}}` | ISO-8601 |
| `{{USER_GOAL}}` | Claude Code 从对话蒸馏的"用户最终目标" |
| `{{PLAN_FILE_PATH}}` | plan 文件的相对路径（相对项目根） |
| `{{PLAN_LANG_OR_MD}}` | 代码块语言，一般 `md` |
| `{{PLAN_FULL_CONTENT}}` | plan 文件**完整**内容 |
| `{{FILES_INLINE_BLOCK}}` | 每个相关文件：三级标题 + 路径 + 完整代码块 |
| `{{PROJECT_CONVENTIONS}}` | CLAUDE.md / AGENTS.md 等的关键约束摘要 |
| `{{CONVENTIONS_SOURCE_PATHS}}` | 上述摘要来自哪几个文件 |
| `{{ALREADY_EXPLORED}}` | "已经试过 X / 排除了 Y / 确认 Z" 列表 |

## 标准调用命令

```bash
codex exec \
  --cd "<PROJECT_ROOT>" \
  --sandbox read-only \
  --skip-git-repo-check \
  -o "<BUNDLE>/response.json" \
  < "<BUNDLE>/request.md"
```

替换：
- `<PROJECT_ROOT>` → 项目绝对路径
- `<BUNDLE>` → `<PROJECT_ROOT>/.codex-bridge/round-1`

**注意**：
- **不传** `--output-schema`（在 codexapi 代理下 502 Bad Gateway）。schema 文件仍保留作为 prompt 里描述结构的参考——request.md §6/§8 引用 `./response.schema.json`，Codex 会按 prompt 描述遵循。
- 用 stdin (`<`) 不用 `"$(cat ...)"`，避免参数超长。
- Claude Code 在读 response.json 后用 `jq` 自行校验 schema required 字段（替代 CLI 协议层校验）。

## response.md 渲染模板

Codex 跑完后，Claude Code 读 `response.json` 并按此渲染给用户：

```markdown
# Codex 审阅结果（plan-review）

## Codex 的任务理解
{response.task_understanding}

## 总体结论
{response.result}

## 关键发现（按类型分组）

### 隐藏假设
{key_findings 中 type=hidden_assumption 的所有 content}

### 我不同意 plan 的地方
{key_findings 中 type=disagreement 的所有 content}

### 风险与陷阱
{key_findings 中 type=risk 的所有 content}

### 我赞同的点
{key_findings 中 type=validation 的所有 content}

## 具体建议

{对每个 specific_suggestions:}
- **{file}**: {change}（原因: {reason}）

## 待拍板的问题
{open_questions 列表，无则"无"}

## Codex 自我标注的不确定性
{uncertainty}
```

## 跑完后 Claude Code 要做什么（v1.1 流程衔接，v1.2 新增）

跑完 codex exec 之后：

1. 读 `response.json` 并跑 8 步 jq 校验（见 SKILL.md step 10）
2. 渲染 `response.md`（用上方模板）
3. **v1.1 流程**（Claude Code 必走，按 SKILL.md F0 "Skill 激活情境下的隐式触发"）：
   - **3a. Pattern Extraction（step 11.5）** —— 对每条 accepted finding（type ∈ risk/hidden_assumption/disagreement）问 3 个问题，写到 `<bundle>/extracted-patterns.md`
   - **3b. Lateral Verification（step 11.6）** —— 按 extracted-patterns.md 搜索方法在项目内执行，candidates 写回
   - **3c. 如有 candidates** → 跑 verification-round（见 [templates/verification-round/prompt-notes.md](../verification-round/prompt-notes.md)）
4. 综合主轮 + 验证轮 → 给用户呈现 plan 修订建议（按"角色分工"discipline，Claude Code 综合后才呈现，不要原文转给用户）

## 失败处理

- `response.json` 不存在：报错"codex exec 失败，查看 bundle/manifest.json 的 codex_exit_code 和 stderr"
- `response.json` 不符合 schema：**CLI 不做协议层拦截**（`--output-schema` 在 codexapi 代理下 502 已移除）。Claude Code 必须本地校验失败后报错——用 jq has + jq type + jq enum + 4 维 dimension 覆盖检查（详见 SKILL.md step 10）
- `specific_suggestions` 为空：可能 Codex 全部赞同 → 在 response.md 注明"无改动建议"
