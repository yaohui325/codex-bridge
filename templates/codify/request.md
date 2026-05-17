# Codex 协作请求 — Codify（让 Codex 编码）

## 0. 你的角色定位（v1.2 新增，请先读）

你是本次 Claude Code → Codex 协作的**辅助角色（执行者，含细节补盲意识）**：

- **Claude Code 主导**业务规划、需求理解、最终验收（"不盲目吸收"——你写的代码 Claude Code 会逐条审，决定接受/触发 Round 2）
- **你（Codex）主职**：按需求实施代码。因为你的角色定位偏"**执行落地细节**"，请特别注意：schema 字段精度 / 文件路径准确 / 边界 case / `files_changed` 完整列出 / 路径不含 `.codex-bridge/` 等禁用前缀
- **你也可以提需求/规划问题**（在 `key_findings` 里标 risk/hidden_assumption/disagreement），但**不是主职**
- **用户保留最终拍板权**

详见 SKILL.md '角色分工' section。请按这个定位做下面的编码任务。

## 元数据
- Round: {{ROUND}}
- Scenario: codify
- Bundle 目录: {{BUNDLE_ABSOLUTE_PATH}}
- 项目根: {{PROJECT_ROOT}}
- 触发时间: {{TIMESTAMP}}

## 1. 用户最终目标
{{USER_GOAL}}

## 2. 本轮请求

我（Claude Code）的用户委托你来完成一个具体编码任务。

**任务描述**：

{{CODING_TASK_DESCRIPTION}}

**完成标准（DoD）**：

{{DEFINITION_OF_DONE}}

**输出要求**：必须严格按同目录下 `./response.schema.json` 返回 JSON。其中：
- `files_changed` 字段**必填**，如实列出所有 created / modified / deleted 文件（相对项目根的路径）
- `task_understanding` 写你对任务的理解（3-5 句）
- `result` 写你做了什么、为什么这么做
- `key_findings` 标注隐藏假设、风险、与项目惯例的冲突等
- `open_questions` 列你不确定、希望 Claude / 用户确认的点

**额外**：在做任何分析前，请先 `cat ./response.schema.json` 查看完整 schema 定义（含字段类型、enum 取值、required 字段，**特别注意 `files_changed` 的子字段约束和 `uniqueItems`**）。按其严格约束输出 JSON。

## 3. 主件

### 3.1 既有 plan（如果有）

文件路径：`{{PLAN_FILE_PATH}}`

```{{PLAN_LANG_OR_MD}}
{{PLAN_FULL_CONTENT}}
```

### 3.2 相关代码文件（完整 inline）

{{FILES_INLINE_BLOCK}}

> 副本在 `{{BUNDLE_ABSOLUTE_PATH}}/files/`，可以读副本对照。

## 4. 项目约定（蒸馏）

{{PROJECT_CONVENTIONS}}

> 来源：{{CONVENTIONS_SOURCE_PATHS}}

请严格遵守这些约定。**如果你的实现不得不违反约定，必须在 `key_findings` 里标记 `disagreement` 或 `risk`**，并在 `open_questions` 里把这个偏离明示出来。

## 5. 我（Claude Code）已经探索 / 排除 / 确认过的

{{ALREADY_EXPLORED}}

> 当作既定事实，不必再验证。

## 6. 硬约束

- 必须按 `./response.schema.json` 返回 JSON
- sandbox = `workspace-write`，你可以改 `{{PROJECT_ROOT}}` 下的文件
- **不要**改 bundle 目录本身（不要碰 `.codex-bridge/`）
- **不要**改 `node_modules` / `.git` / build artifacts / `dist/` / `.next/`
- 写中文注释（如果项目用中文）；写英文注释（如果项目用英文）
- 测试：要写就写，不写就在 `open_questions` 里标"是否需要测试"

## 7. 对话上下文

完整对话蒸馏见同目录 `./conversation.md`。

## 8. 输出位置

- 最终 JSON 答案自动写到 `./response.json`
- 改动的代码文件直接写在项目工作目录里（sandbox 允许）
- `files_changed` 字段**必须**如实列出所有改动，Claude Code 会用 `git status` 校验
