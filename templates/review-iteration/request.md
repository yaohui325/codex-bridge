# Codex 协作请求 — Review Iteration（Round 2，终轮）

## 0. 你的角色定位（v1.2 新增，请先读）

你是本次 Claude Code → Codex 协作的**辅助角色（基于 Claude review 的精确执行者）**：

- **Claude Code 主导**：已基于 Round 1 给出 review 意见。本 Round 2 你按 review 意见修改代码。**Claude Code 是最终决策方**（"不盲目吸收"——你的修改 Claude Code 会再审）
- **你（Codex）主职**：精确执行 Claude review 意见（**不要为了迎合 review 强行扩大改动范围**，最小修改）。你的角色定位偏"执行落地细节"——特别注意 schema 字段 / 文件路径 / 改动清单 / 边界 case
- **你也可以**在 key_findings 里指出 review 意见本身的问题（type=disagreement）或新引入的 risk，但**不是主职**
- **用户保留最终拍板权**

详见 SKILL.md '角色分工' section。请按这个定位做本轮修改。

## 元数据
- Round: 2（**终轮**，不允许 Round 3）
- Scenario: review-iteration
- Bundle 目录: {{BUNDLE_ABSOLUTE_PATH}}
- 项目根: {{PROJECT_ROOT}}
- 触发时间: {{TIMESTAMP}}
- 前序轮次: Round 1 codify（完整内容见下方 §9）

## 1. 用户最终目标
{{USER_GOAL}}

## 2. 本轮请求

Round 1 你已经按 codify 场景做了一版实现。Claude Code 看完之后给了 review 意见（见下方 §9.3）。

请基于 review 意见**修改你 Round 1 的代码**，注意：

- 这是**最后一轮**，没有 Round 3
- 优先解决 Claude review 提出的具体问题
- **不要做超出 review 范围的额外改动**（不要"顺便重构"）
- 如果某条 review 意见你不同意，**不要为了迎合 review 强行改**；只做与目标一致的最小调整，并在 `key_findings` 里标 `disagreement` 说明未采纳原因

**输出要求**：必须按同目录 `./response.schema.json` 返回 JSON。
- `files_changed` 字段**必填**（本轮新增的改动）
- `task_understanding` 写你怎么理解这轮的修改目标
- `result` 写你这轮做了什么、为什么
- `key_findings` 重点标：
  - `validation` = 哪些 review 意见接受并按其改了
  - `disagreement` = 哪些 review 意见没接受、为什么
  - `risk` = 改完后引入的新风险

**额外**：在做任何分析前，请先 `cat ./response.schema.json` 查看完整 schema 定义（含字段类型、enum 取值、required 字段、`files_changed` 子字段约束）。按其严格约束输出 JSON。

## 3. 主件

### 3.1 既有 plan（如果有）

文件路径：`{{PLAN_FILE_PATH}}`

```{{PLAN_LANG_OR_MD}}
{{PLAN_FULL_CONTENT}}
```

### 3.2 相关代码文件（**Round 1 之后的最新状态**）

{{FILES_INLINE_BLOCK}}

> 这些是 Round 1 你改完之后的文件状态——是你 Round 2 的起点。
> 副本在 `{{BUNDLE_ABSOLUTE_PATH}}/files/`。

## 4. 项目约定（蒸馏）

{{PROJECT_CONVENTIONS}}

> 来源：{{CONVENTIONS_SOURCE_PATHS}}

## 5. 我（Claude Code）已经探索 / 排除 / 确认过的

{{ALREADY_EXPLORED}}

## 6. 硬约束

- 必须按 `./response.schema.json` 返回 JSON
- sandbox = `workspace-write`
- **这是终轮**，不允许 Round 3
- 不要碰 `.codex-bridge/`
- **不要做超出 review 范围的"顺便重构"**
- 用**中文**回答

## 7. 对话上下文

完整对话蒸馏见同目录 `./conversation.md`。

## 8. 输出位置

- 最终 JSON 答案自动写到 `./response.json`
- 改动代码直接写在项目工作目录
- `files_changed` 必须如实列出 Round 2 **本轮新增**的所有改动（不要重复列 Round 1 改过但 Round 2 没动的文件）

## 9. 前序轮次（Round 1 完整 inline）

### 9.1 Round 1 Request（我上一轮给你的请求）

Round 1 bundle: `{{ROUND_1_BUNDLE_PATH}}`

```markdown
{{ROUND_1_REQUEST_FULL}}
```

### 9.2 Round 1 Response（你上一轮的回答）

```json
{{ROUND_1_RESPONSE_FULL}}
```

### 9.3 Claude Review（看完 Round 1 之后我对你的反馈）

```markdown
{{CLAUDE_REVIEW_FULL}}
```

**这一节是本轮的核心**——你要解决的就是 §9.3 里提到的问题。
