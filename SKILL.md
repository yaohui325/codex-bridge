---
name: codex-bridge
description: 显式触发的 Claude Code → Codex CLI 桥接 skill。把对话上下文 / plan / 相关文件 / 项目约定外化为 bundle 目录，调用 codex exec 并用 response.schema.json 作结构参考 + Claude Code jq 后处理校验。适用 4 场景（v1.1 起）：plan 审阅、Codex 编码、Claude-Codex 互审最多 2 轮迭代、verification-round 验证轮。
---

# codex-bridge

## 这个 skill 解决的问题

Claude Code 通过 Bash 直接调用 `codex exec` 时，只有 prompt 字符串能传给 Codex。结果：
- 当前对话讨论过的方向、ruled-out 的方案 → 丢失
- plan / 主件代码引用但没 inline 的文件 → Codex 看不到
- 项目约定（CLAUDE.md / AGENTS.md） → 丢失
- "我已经试过 X、确认 Y" 等隐性信息 → 丢失

本 skill 把"显性外化上下文"变成强制工作流。

## 角色分工：Claude Code 全面把控 / Codex 补细节盲点（v1.2 新增，**根本设计原则**）

Claude Code 和 Codex 在协作中**角色非对称、能力互补**：

| 角色 | 定位 | 主要职责 |
|---|---|---|
| **Claude Code（主）** | 全面把控者 + 聪明规划者 | 业务逻辑规划 / 工作流编排 / bundle 打包 / 上下文外化 / 用户接口 / 最终决策（"不盲目吸收"discipline）/ 调用 Codex 的时机和场景 |
| **Codex（辅）** | **细节补盲者** | **主职**：补 Claude Code 在**执行落地细节**的盲点；按 schema 输出结构化 finding，不直接做最终决策 |

**Codex 补的"细节维度"**：
- **schema 字段引用准确性**（Claude Code 容易写 `finding.reason` 但实际 schema 字段是 `finding.content` —— Round 4 / Round 7 都证实）
- **文件位置 / section 引用准确性**（Claude Code 容易引用不存在的 section —— Round 4 / Round 7 都证实）
- **实施步骤的边界 case**（fail vs warn 选择 / 错误处理 / 并发安全 / 防递归）
- **测试覆盖完整性**（fixture 是否含正例 + 多种负例 + 组合边界）
- **增量编辑后的全篇一致性**（远端文档 / heading / frontmatter 是否同步）
- **隐藏假设暴露**（plan 没明说的事）
- **文档真源冲突**（多处描述同一规则但措辞不一致）

**Codex 的副职（允许但不是主要价值）**：发现业务逻辑 / 规划层面的问题也**欢迎**指出，但**不是 Codex 的核心价值**。前 7 轮 dogfood 证明 Codex 的最大价值在 Claude Code **单干会漏的细节**——业务规划上 Claude Code 通常更强（因为它有完整对话上下文）。

**为什么这样设计**：
- Claude Code 与用户直接对话，知道完整 context 和业务意图，适合做战略 + 用户接口
- Codex 独立于 Claude Code，能跳出 Claude Code 的"自圆其说"盲点（dogfood 7 轮证据）
- Claude Code 把战略决策权让出去 → "不盲目吸收"discipline 崩 → skill 退化为 "Claude Code 转述 Codex 的话"，失去核心价值

**含义（每次 Claude Code 调 Codex 时记住）**：
- Claude Code 决定**何时**调 Codex / **什么 scenario** / **如何打包 bundle** / **如何综合 Codex 反馈**
- Codex 给 finding 和 suggestion，但**接受/拒绝/部分接受始终是 Claude Code 的判断**
- 用户保留**最终拍板权**——Claude Code 综合后的修订版 plan / 代码呈现给用户

**反例（违反角色分工）**：
- ❌ Claude Code 让 Codex 直接改代码并接受不审 → 失去 control
- ❌ Codex 说"建议改 X"，Claude Code 不判断直接应用 → 盲目吸收
- ❌ Claude Code 把 Codex finding 原文转给用户让用户自己决定 → 推卸综合责任
- ❌ Codex 试图主导战略 / 用户问 Codex "用哪种架构"（直接让 Codex 回答）→ 角色错位（应由 Claude Code 综合后回答）

## 触发条件

**自然语言触发词**：
- 让 Codex 审一下 / Codex 看看这个 plan / Codex 复核
- 交给 Codex 编码 / 让 Codex 实现 / 用 Codex 写
- Codex review / 跑 Codex / Codex 二审
- 让 Codex 改一下 / Codex 修改一下

**显式 slash**：`/codex-bridge`

### Skill 激活情境下的隐式触发（v1.2 新增）

**前提**：用户已主动触发 codex-bridge skill（通过 `/codex-bridge` 或自然语言触发词；见上方"自然语言触发词"主段）。

**规则**：在 skill 已激活的同一**用户任务**里，**Claude Code 写完任何 plan 文件后，必须先用 plan-review scenario 让 Codex 审一遍**（不需要用户每次再说"让 Codex 审"），综合 finding（按 step 11.5/11.6 走 pattern extraction）后再呈现 plan 给用户。

**激活范围**：当前**用户任务 / 当前 codex-bridge 工作流**（不是机械意义上的"整个对话窗口"——长会话、压缩后的会话、用户切换到无关任务都不算激活）。

**失活条件**（出现任一即失活）：
- 用户明确切换话题（如"先放下 codex-bridge，帮我看下 X"）
- 用户明确表示不要用 Codex（如"这事不用 codex 了"）
- 当前用户任务交付结束（plan 实施完毕 / 用户表示满意）
- 进入纯解释 / 闲聊 / 元讨论而非任务执行

**重审条件（防循环）**：同一 plan 经 Codex 审过后**小修不重新触发**；**只有重大改写**（核心机制变更 / scope 重大扩展 / 新增设计决策）才重新触发 plan-review。防止"修一处就重审一遍"的无限循环。

**为什么不是"自动触发"**：
- skill 是否启用**由用户决定**——用户没说要用 codex-bridge，Claude Code 不应自作主张调 Codex
- 一旦用户决定用 skill 了，"Claude Code 写完 plan 不能直接给用户看，必须先经 Codex" 是 **skill 内部的隐式工作流**，不需要用户每个 plan 都再次确认

**正反例**：
- ✅ 用户："帮我用 codex-bridge 规划这个小功能" → Claude Code 写 plan → **隐式**调 plan-review → 综合 → 呈现 plan 给用户
- ✅ 用户："/codex-bridge 帮我做..." → 同上
- ✅ 用户在已激活的 codex-bridge 任务里继续："那再帮我规划下一步" → Claude Code 写 plan → **仍然隐式**调（skill 还激活着）
- ❌ 用户："帮我规划一下做个 X 功能"（**没提 codex / skill**）→ Claude Code 写 plan → **不应该**自作主张调 Codex
- ❌ 用户："让 Claude Code 改一下 README"（**与 codex 无关**）→ 不应该调

**例外**：plan mode 限制 codex exec。Plan mode 内的 plan 视为 **provisional draft**，ExitPlanMode 后立即跑 plan-review，综合 finding 后再实施或再请用户拍板。

**理由**：Claude Code 单干写 plan 经常出 2 类问题——schema 字段误读、引用不存在的文件位置（Round 4 / Round 5 / Round 7 都验证了）。让 Codex 在用户看到 plan 前先过一遍，能把 v1 plan 的"草稿质量"提升到 v2 的"审过的质量"。

## 四个场景（v1.1 起）

| 场景 | 用途 | sandbox |
|---|---|---|
| `plan-review` | 让 Codex 审计 plan / 设计 / 代码 | `read-only` |
| `codify` | 让 Codex 写代码完成任务 | `workspace-write` |
| `review-iteration` | 基于 Claude review 让 Codex 修改 | `workspace-write` |
| `verification-round` (v1.1) | 验证 Claude Code 从主轮 finding 提取的 patterns 和 candidates（focused verification） | `read-only` |

`codify` + `review-iteration` 组合最多两轮，第二轮后强制结束。
`verification-round` 用 `manifest.purpose` 字段标记，**不**占 `codify` 的 2 轮硬上限。

## 强制执行清单（每次必走）

1. **识别场景**：plan-review / codify / review-iteration / verification-round
2. **创建 bundle 目录**：跑 `scripts/create-bundle.sh <scenario>`（推荐——自动建目录、复制 schema、初始化 manifest）；或手动 `mkdir -p <project>/.codex-bridge/round-<n>/files`
3. **过 [checklist](./checklist.md) self-audit**
4. **填写 request.md**：复制对应场景的 `templates/<scenario>/request.md`，替换所有 `{{VAR}}`
5. **inline 文件**：把 plan 引用的所有相关文件**完整**复制到 `bundle/files/`（效果优先，不省 token）
6. **蒸馏 conversation.md**：
   - 最近 15 条人类↔Claude 交互，每条 1-3 行人话总结
   - 此前会话摘要 1 段
   - 当前 session JSONL 绝对路径（结构见 [jsonl-guide](./jsonl-guide.md)）
7. **拷贝 schema**：把对应场景的 `templates/<scenario>/response.schema.json` 复制到 bundle
8. **写 manifest.json**：见 [conventions.md](./conventions.md)
9. **调用 codex**：
   ```bash
   codex exec \
     --cd "<project-absolute-path>" \
     --sandbox <read-only|workspace-write> \
     --skip-git-repo-check \
     -o "<bundle>/response.json" \
     < "<bundle>/request.md"
   ```

   **注意**：
   - **不要**用 `--output-schema`——在 codexapi 代理下会触发 502 Bad Gateway。schema 文件仍保留作为 prompt 里描述结构的参考（在 request.md §6 / §8 引用），但 CLI 不传它。
   - **必须**用 stdin (`< request.md`) 而不是 `"$(cat ...)"` 命令参数，避免长 inline 触发 shell 参数长度限制。
   - `--skip-git-repo-check` 适用 greenfield 目录；对 git 仓库也无害。
10. **读回 response 并严格校验**（替代 `--output-schema` 协议层校验）：

    a) **JSON 合法**: `jq empty <bundle>/response.json`

    b) **Required 字段存在**:
       ```bash
       jq -e 'has("task_understanding") and has("result") and has("key_findings") and has("specific_suggestions") and has("open_questions") and has("uncertainty")' <bundle>/response.json
       ```

    c) **字段类型正确**:
       ```bash
       jq -e '
         (.task_understanding | type == "string") and
         (.result | type == "string") and
         (.key_findings | type == "array") and
         (.specific_suggestions | type == "array") and
         (.open_questions | type == "array") and
         (.uncertainty | type == "string")
       ' <bundle>/response.json
       ```

    d) **`key_findings[].type` 全在 enum 内**:
       ```bash
       jq -e '[.key_findings[].type] | all(. == "hidden_assumption" or . == "disagreement" or . == "risk" or . == "validation")' <bundle>/response.json
       ```

    e) **plan-review 场景额外**：每个 `key_findings` 含 `dimension` 且属于 4 维枚举：
       ```bash
       jq -e '[.key_findings[].dimension] | all(. == "rationality" or . == "hidden_assumptions" or . == "conventions" or . == "scope_control")' <bundle>/response.json
       ```

    f) **codify / review-iteration 场景额外**：`has("files_changed")` + `files_changed.{created,modified,deleted}` 都是数组：
       ```bash
       jq -e 'has("files_changed") and (.files_changed.created | type == "array") and (.files_changed.modified | type == "array") and (.files_changed.deleted | type == "array")' <bundle>/response.json
       ```

    g) **plan-review 场景额外**：4 维 `dimension` 必须**全覆盖**（不只单项 enum 合法）：
       ```bash
       DIM_COUNT=$(jq -r '[.key_findings[].dimension] | unique | length' <bundle>/response.json)
       [ "$DIM_COUNT" -ge 4 ] || echo "WARN: 只覆盖 $DIM_COUNT / 4 维度（缺维 = 审阅不充分）"
       ```

    h) **任一检查失败** → 报错并保留 bundle 让用户决定（重跑 / 人工降级）
11. **渲染 response.md**：把 JSON 转成人类可读 markdown 给用户看

11.5. **Pattern Extraction（v1.1 新增，判断式 + 强制给理由）**

    对每条 accepted finding（`type` ∈ `risk` / `hidden_assumption` / `disagreement`）问 3 个问题，写到 `<bundle>/extracted-patterns.md`：

    a) `finding.content` + `related_files` 指向什么根因？（参考 Codex 在 `result` 字段的整体定性）
    b) 根因是否可能在项目内其他地方复现？
    c) 如何具体搜索验证？

    **强制纪律**：
    - 提取的每个 pattern **必须**给"为什么这是 pattern" 理由
    - 判定"无 pattern" 的每条 finding **必须**给"为什么不是 pattern" 理由
    - 空白或隐式跳过 = checklist fail

    如果**全部 findings 都判 pattern 无**：`extracted-patterns.md` 仅含"无 pattern" 段（每条仍要给理由），跳到 step 12。

11.6. **Lateral Verification + 验证轮（v1.1 新增，如有 pattern）**

    a) 按 `extracted-patterns.md` 里的搜索方法在项目内执行（grep / find / cat）
    b) candidates 写回 `extracted-patterns.md` "横向查证结果" section
    c) 如有 candidates：
       - 跑 `scripts/create-bundle.sh verification-round`
       - 手动设 `manifest.purpose = "verify round-<N> extrapolations"`
       - inline 主轮 `response.json` + `extracted-patterns.md` 到验证轮 `files/`
       - 跑 codex exec（同 plan-review 调用方式）
       - 校验返回（**verification schema** 的 7 步 jq 校验，见 [templates/verification-round/prompt-notes.md](./templates/verification-round/prompt-notes.md)）
       - 综合主轮 finding + 验证轮 verdict 更新 v2 plan / 代码
    d) 如无 candidates：跳到 step 12（明示）

12. **判定下一步**（如走了 11.6 验证轮，**必须**综合主轮 + 验证轮的 verifications & additional_findings）：
    - `plan-review`：结束
    - `codify` Round 1：写 `claude-review.md` → 评估是否需要 Round 2
    - `review-iteration` Round 2：必须结束，不允许 Round 3
    - `verification-round`：本身是 sub-round，决策由触发它的主轮承担

## 不要做的事

- ❌ 用单行 prompt 字符串调 codex（绕过 bundle）
- ❌ 省略 inline 文件（Codex 看不到就没意义）
- ❌ 超过 2 轮迭代
- ❌ 异步 polling（Bash 调用本身同步阻塞）
- ❌ 不写 conversation.md

## 失败处理

- `codex exec` 返回非 0：报错给用户，保留 bundle 供调试，更新 `manifest.status="failed"`
- `response.json` 不符合 schema：Claude Code 用 jq 验证 required 字段（CLI 不再做协议层校验，因 `--output-schema` 在 codexapi 代理下 502）；报错让用户决定重跑或人工降级
- `response.json` 不存在但 `exit code = 0`：异常情况，保留 stderr 供诊断
- codex 进程超时 / 用户中断（SIGINT）：保留 bundle，`manifest.status="failed"`，向用户提示
- 文件 inline 失败：必须报错，不能静默跳过
- 无 git 项目（codify 需要 git 校验）：见 [codify prompt-notes](./templates/codify/prompt-notes.md) 的 mtime 快照 fallback
- JSONL 在 sandbox 下不可读：见 [jsonl-guide](./jsonl-guide.md) 的 sandbox 验证步骤
- **pattern extraction 跳过且未给理由**（v1.1）：checklist fail，要求重写 `extracted-patterns.md` 含理由
- **验证轮 codex exec 失败**（v1.1）：**不**阻断主流程；记录到 `manifest.notes` 警告，Claude Code 用主轮 findings 继续

## 相关文档

- [checklist.md](./checklist.md) — 写 bundle 前必过的 self-audit
- [conventions.md](./conventions.md) — bundle 目录与文件约定
- [jsonl-guide.md](./jsonl-guide.md) — Claude Code 会话 JSONL 结构指南
- `templates/plan-review/` — plan 审阅场景模板
- `templates/codify/` — Codex 编码场景模板
- `templates/review-iteration/` — Codex 二轮修改场景模板
- `templates/verification-round/` — Codex 验证轮场景模板（v1.1 新增）
