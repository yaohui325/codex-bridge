# Codex 验证请求 — Round {{MAIN_ROUND}} extrapolations

## 0. 你的角色定位（v1.2 新增，请先读）

你是本次 Claude Code → Codex 协作的**辅助角色（focused verifier，含细节补盲意识）**：

- **Claude Code 主导**：已在主轮基础上提取 patterns + 横向查证出 candidates。本验证轮你**仅判定**每个 candidate 是不是同类问题。**Claude Code 是最终决策方**
- **你（Codex）主职**：focused verification（不是完整 plan-review）+ 主动找 Claude Code 漏掉的 **additional_findings**（你的细节补盲价值在这里发挥）
- **你也可以**在 reasoning 中指出 Claude Code 的 pattern 抽取本身有问题，但**不是主职**——主职是 verify candidates
- **用户保留最终拍板权**

详见 SKILL.md '角色分工' section。请按这个定位做本验证。

## 元数据
- Round: {{ROUND}}（**验证轮**，scenario=verification-round；不占 codify 2 轮硬上限）
- 主轮 round: {{MAIN_ROUND}}
- 主轮 bundle: {{MAIN_ROUND_BUNDLE}}
- Bundle 目录: {{BUNDLE_ABSOLUTE_PATH}}
- 项目根: {{PROJECT_ROOT}}
- 触发时间: {{TIMESTAMP}}

## 1. 主轮上下文（Codex Round {{MAIN_ROUND}} 已找到的 findings）

主轮 response.json 路径: `{{MAIN_ROUND_BUNDLE}}/response.json`
副本: `./files/round-{{MAIN_ROUND}}-response.json`

主轮你（Codex）找到的 findings 摘要：

{{MAIN_ROUND_FINDINGS_SUMMARY}}

## 2. Claude Code 从主轮提取的 patterns

完整记录见 `./files/extracted-patterns.md`。这里给摘要：

{{EXTRACTED_PATTERNS_SUMMARY}}

## 3. Claude Code 外推的 candidate instances

每个 candidate 都附 Claude Code 的"为什么我认为是同类问题"理由。完整见 `extracted-patterns.md`：

{{CANDIDATES_SUMMARY}}

## 4. 你的任务（**focused verification**，不是完整 plan-review）

对每个 candidate (X1, X2, Y1, ...) 标：

- `confirmed`: 是同一类问题（给 1-2 句理由）
- `refuted`: 不是同一类问题（给 1-2 句理由）
- `partial`: 有部分相似但不完全（给 1-2 句理由）
- `unsure`: 信息不够（列出还需要看什么）

**额外信号**：如果你在验证过程中**新发现了** Claude Code 没列出的同类问题，请放到 `additional_findings`。

**注意**：本轮**不是**让你重新做 4 维度审阅。只对 candidates 做判断，不要试图扩展到整个 plan 重审。

## 5. 项目约定

（同 plan-review，未变化）项目无 CLAUDE.md / AGENTS.md。Claude Code skill 通用约定：SKILL.md frontmatter / 中文项目 / templates 子目录 / 渐进披露。

## 6. 硬约束

- 必须按 `./response.schema.json` 返回 JSON
- 本次 sandbox = `read-only`，不要试图改任何文件
- 用**中文**回答
- `task_understanding` 写 3-5 句你对任务的理解
- 每个 `verification` **必须**含 `reasoning`（不能只标 verdict）
- **额外**：在做判断前，请先 `cat ./response.schema.json` 查看完整 schema 定义

## 7. 对话上下文

完整对话蒸馏见同目录 `./conversation.md`。

## 8. 输出位置

- `response.json`（codex exec -o 自动写）
- **不传** `--output-schema`（codexapi 代理 502，已成既定事实）
