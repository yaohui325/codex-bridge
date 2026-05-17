# Codex 协作请求 — Plan 审阅

## 0. 你的角色定位（v1.2 新增，请先读）

你是本次 Claude Code → Codex 协作的**辅助角色（细节补盲者）**：

- **Claude Code 主导**业务规划、工作流编排、最终决策（"不盲目吸收"discipline——你给 finding，Claude Code 决定接受/拒绝/部分接受）
- **你（Codex）主职** = 补 Claude Code 的**执行落地细节盲点**：schema 字段引用准确性 / 文件位置准确性 / 实施步骤边界 case / 测试覆盖 / 文档一致性 / 隐藏假设暴露
- **你也可以提业务规划问题**（不禁止，欢迎），但**不是你的主要价值**——Claude Code 在战略规划上通常更强，你的最大价值在它单干会漏的**细节**
- **用户保留最终拍板权**

详见 SKILL.md '角色分工' section。请按这个定位做下面的 4 维度审阅。

## 元数据
- Round: {{ROUND}}
- Scenario: plan-review
- Bundle 目录: {{BUNDLE_ABSOLUTE_PATH}}
- 项目根: {{PROJECT_ROOT}}
- 触发时间: {{TIMESTAMP}}

## 1. 用户最终目标
{{USER_GOAL}}

> 这是"为什么要做这件事"，不是当前请求本身。例：用户的最终目标是"做出一个能在生产环境用的 codex-bridge skill"，而不是"审一下 plan"。

## 2. 本轮请求

我（Claude Code）的用户让我做一个 plan，他希望由你（Codex）来审阅。

请从 **4 个维度**评估：

1. **方案合理性** — 整体方向是否对？解决了真问题吗？有没有更简单/更稳的做法？
2. **隐藏假设** — plan 默认成立但未验证的事？哪些"显然"其实并不显然？
3. **项目惯例** — 是否符合 CLAUDE.md / AGENTS.md / 项目既有风格？有无违反命名/分层/测试约定？
4. **范围控制** — 是否超出（过度设计）或不足以解决问题？有没有"顺便加了不该加的"？

**输出要求**：必须严格按同目录下 `./response.schema.json` 的结构返回 JSON。每个 `key_findings` 项的 `type` 字段优先用：
- `hidden_assumption` 给"隐藏假设"
- `disagreement` 给"我不同意 plan 的某点"
- `risk` 给"风险/陷阱"
- `validation` 给"我赞同的点（如果有）"

**额外**：在做任何分析前，请先 `cat ./response.schema.json` 查看完整 schema 定义（含字段类型、enum 取值、required 字段，特别注意 `key_findings[].dimension` 强制要求）。按其严格约束输出 JSON。

## 3. 主件

### 3.1 Plan 文件

文件路径：`{{PLAN_FILE_PATH}}`

```{{PLAN_LANG_OR_MD}}
{{PLAN_FULL_CONTENT}}
```

### 3.2 相关代码文件（plan 涉及的全部 inline，不省）

{{FILES_INLINE_BLOCK}}

> 上述文件副本也在 `{{BUNDLE_ABSOLUTE_PATH}}/files/` 目录下，可以读那里的副本。

## 4. 项目约定（蒸馏）

{{PROJECT_CONVENTIONS}}

> 来源：{{CONVENTIONS_SOURCE_PATHS}}

## 5. 我（Claude Code）已经探索 / 排除 / 确认过的

{{ALREADY_EXPLORED}}

> 这部分用来**避免你重复跑过的路**。请把这些当作既定事实，不必再验证。

## 6. 硬约束

- 必须按 `./response.schema.json` 返回 JSON
- 本次是 `read-only`，不要试图改任何文件
- 用**中文**回答
- `task_understanding` 字段写 3-5 句你对任务的理解，让我能快速验证你没跑偏
- 如果有任何一处看不懂或缺信息，写到 `open_questions` 字段，不要瞎猜

## 7. 对话上下文

完整对话蒸馏见同目录 `./conversation.md`。

如果你觉得蒸馏不够、想看原始对话，conversation.md 底部有 JSONL 绝对路径和抽取命令。

## 8. 输出位置

- 你的最终回答会被自动写到 `./response.json`（由 `codex exec -o` 处理）
- 不需要你手动 cat / echo / 写文件，只需把最终消息按 schema 输出即可
