# codex-bridge

> 显式触发的 **Claude Code → Codex CLI 桥接 skill**。把对话上下文 / plan / 相关文件 / 项目约定外化为 bundle 目录，调 `codex exec` 拿回结构化 JSON 响应 + Claude Code 用 jq 后处理校验。

**核心命题**：Claude Code 调 Codex 时，**上下文是显性的、结构化的、可机械校验的**，而不是塞到 prompt 字符串里靠 LLM 猜。

---

## 这个 skill 解决什么问题

当 Claude Code 通过 Bash 直接调用 `codex exec` 时，只有 prompt 字符串能传给 Codex。结果：

- 当前对话讨论过的方向、ruled-out 的方案 → **丢失**
- plan / 主件代码引用但没 inline 的文件 → Codex **看不到**
- 项目约定（CLAUDE.md / AGENTS.md） → **丢失**
- "我已经试过 X / 确认 Y" 等隐性信息 → **丢失**

本 skill 把"显性外化上下文"变成**强制工作流**——Claude Code 调 Codex 前必须先把所有相关信息打包成一个磁盘 bundle，调 `codex exec` 拿回结构化 JSON 响应。

---

## 角色分工（v1.2 起，**根本设计原则**）

| 角色 | 定位 | 主要职责 |
|---|---|---|
| **Claude Code（主）** | 全面把控者 + 聪明规划者 | 业务规划、工作流编排、bundle 打包、用户接口、最终决策（"不盲目吸收"discipline） |
| **Codex（辅）** | **细节补盲者** | 补 Claude Code 在 schema 字段 / 文件引用 / 边界 case / 测试覆盖 / 文档一致性 / 隐藏假设等**细节维度**的盲点 |

**Codex 的副职**：发现业务规划问题也欢迎，**但不是主职**——Claude Code 在战略上通常更强（它有完整对话上下文），Codex 的最大价值在它**单干会漏的细节**。

详见 [SKILL.md "角色分工" section](./SKILL.md#角色分工claude-code-全面把控--codex-补细节盲点v12-新增根本设计原则)。

---

## 4 个场景

| 场景 | 用途 | sandbox |
|---|---|---|
| `plan-review` | 让 Codex 审计 plan / 设计 / 代码 | `read-only` |
| `codify` | 让 Codex 写代码完成任务 | `workspace-write` |
| `review-iteration` | 基于 Claude review 让 Codex 修改（Round 2，硬上限） | `workspace-write` |
| `verification-round` (v1.1) | 验证 Claude Code 从主轮 finding 提取的 patterns 和 candidates | `read-only` |

---

## Quick start

### 安装

```bash
git clone <this-repo-url> /tmp/codex-bridge
cd /tmp/codex-bridge
./install.sh
```

会自动：
1. 检查依赖（`jq`、`bash 4+`、`codex` CLI）
2. 软链到 `~/.claude/skills/codex-bridge`
3. 验证 Claude Code 能识别 skill

### 使用

在 Claude Code 对话里说：

```
让 Codex 审一下这个 plan
```

或显式 slash：

```
/codex-bridge
```

skill 自动接管，按 SKILL.md 强制执行清单走 12 步流程（含 v1.1 Pattern Extraction + Lateral Verification）。

---

## Skill 激活情境下的隐式触发（v1.2 关键规则）

⚠️ **重要**：一旦用户激活了 skill（通过自然语言触发词或 `/codex-bridge`），**在那个用户任务里 Claude Code 写完任何 plan 都必须先用 plan-review 让 Codex 审一遍**，综合后才呈现给用户。

这**不是**无条件"自动触发"——skill 是否启用仍由用户决定。但一旦启用，"Claude Code 写完 plan 不能直接给用户看，必须先经 Codex" 是 skill 内部的**隐式工作流**，用户不需要每个 plan 都重复说"让 Codex 审"。

详见 [SKILL.md "Skill 激活情境下的隐式触发" section](./SKILL.md#skill-激活情境下的隐式触发v12-新增)。

---

## 核心工作流（12 + 2 步简化版）

```
[1-2] 用户触发 → Claude Code 识别场景
        ↓
[3] scripts/create-bundle.sh 建骨架
        ↓
[4-8] Claude Code 填 bundle：
      - request.md (按场景模板)
      - files/ (inline 所有相关文件)
      - conversation.md (蒸馏 + JSONL 路径)
      - manifest.json (元数据)
        ↓
[9] codex exec (sandbox=read-only|workspace-write)
        ↓
[10] Claude Code 用 jq 做 8 步 schema 校验
        ↓
[11] 渲染 response.md (人话给用户看)
        ↓
[11.5 v1.1] Pattern Extraction (判断式 + 强制给理由)
        ↓
[11.6 v1.1] Lateral Verification → 如有 candidates 触发 verification-round
        ↓
[12] 决策下一步 (按场景: 结束 / codify Round 2 / 强制终轮)
```

完整 12 步见 [SKILL.md "强制执行清单"](./SKILL.md#强制执行清单每次必走)。

---

## 实战 dogfood 证据

本 skill 经过 **7 轮**自我审计 + 真实小功能审阅：

| Round | 内容 | Codex 判断 | validation 占比 |
|---|---|---|---|
| 1-3 | v1.0 自审三轮 | 不可生产 → 偏充分 → **接近生产可用** | — |
| 4 | v1.0 实战（plan-review on 小功能 plan） | 发现 **2 个事实错误** (schema 字段误读 / 引用错文件位置)——证明 skill 真有用 | — |
| 5 | v1.1 dogfood 主轮 | "部分值得" + 14 finding | 21% |
| 6 | v1.1 dogfood 验证轮 | 10 confirmed + 7 additional → **信号放大 2.2x** | — |
| 7 | v1.2 dogfood + F0 trigger rule 首例 | **"需小调"** | **36% (↑15pp)** |

每轮 bundle 完整保留可复盘——dogfood 不是营销话术，是**真审了 7 轮**的工程史。

---

## 文档地图

| 文档 | 内容 |
|---|---|
| [SKILL.md](./SKILL.md) | 主指令（角色分工 / 触发条件 / 4 场景 / 强制执行清单 / 失败处理） |
| [checklist.md](./checklist.md) | 写 bundle 前 self-audit |
| [conventions.md](./conventions.md) | bundle 命名 + 目录约定 + Round 编号语义（业务迭代 / 审计 round / 验证 round） |
| [jsonl-guide.md](./jsonl-guide.md) | Claude Code 会话 JSONL 结构指南 |
| [templates/](./templates/) | 4 个 scenario 的 `request.md` + `response.schema.json` + `prompt-notes.md` |
| [scripts/](./scripts/) | `create-bundle.sh`（建骨架）+ `validate-bundle.sh`（机械校验 + verification-round 专用检查） |

---

## v1.3 Roadmap（开源后社区可贡献）

8 处 nice-to-have 增强 + 1 个端到端测试 gap，**全部欢迎 PR**：

- **R1**: validate-bundle 检查 `manifest.claude_session_jsonl` required 字段
- **R2**: `previous_rounds[]` 元素绝对路径 + 路径存在性检查
- **R4**: codify schema `uniqueItems` 的 jq 后处理校验
- **R5**: `manifest.codex_command / codex_exit_code` 完成后必更新
- **R6**: `files_changed` 路径禁用规则（`.codex-bridge/` / `.git/` / `node_modules/` 等）jq 检查
- **R7**: validate-bundle 加 `--post-response` 模式（区分 bundle 创建后 vs codex 跑完后）
- **R8**: Claude decision log（response.md 新加 section）让 "accepted finding" 概念稳定

**最优先 todo（不在 v1.3 但比 nice-to-have 更重要）**：跑一次**真实 codify 端到端测试**——是 v1.0 时遗留的 gap。所有 dogfood 都跑过 plan-review，但 codify 场景（让 Codex 真改代码 + workspace-write sandbox）从未端到端验证过。

---

## 已知限制

- **codex CLI 代理兼容性**：在 `codexapi`（`api.codexapi.space`）代理下，`--output-schema` flag 触发 502 Bad Gateway。本 skill **不使用** `--output-schema`，改在 prompt 里描述 schema + Claude Code 用 jq 后处理校验。其他代理（OpenAI 直连等）未测试，欢迎反馈
- **macOS 假设**：脚本用了 `stat -f` (BSD)，Linux 需要 `stat -c` (GNU)。Linux 兼容性是 v1.3 候选
- **路径含空格**：已测试支持（项目根可以是 `/Users/foo/hezuo -skill` 这种含空格的路径）
- **中文 hardcoded**：所有文档和日志都是中文，与项目风格一致；翻译欢迎 PR

---

## Contributing

Issues + PRs welcome。特别欢迎：

- v1.3 roadmap 任一条的实现
- **真实 codify 端到端测试用例 + dogfood 报告**（最大缺口）
- 其他 codex CLI 代理（非 codexapi）的兼容性测试报告
- Linux 兼容性（`stat -c` 替代 `stat -f`）
- 英文 README 翻译

提 PR 前请：

1. 在 `~/.claude/skills/codex-bridge/scripts/validate-bundle.sh` 验证 round-1 到 round-N 都过（除 round-1 是历史 artifact）
2. 如果改了 SKILL.md / templates，**用 skill 自身的 plan-review 流程跑一遍**审改动（"吃自己的狗粮"）

---

## 致谢

本 skill 在 **7 轮** dogfood 中由 Claude Code（主）和 Codex（辅）协作迭代——所有 round bundle、Codex 反馈、Claude 决策记录、3 次 user 关键纠正（"不盲目吸收"、"不是自动触发"、"角色分工"）都可在原项目 git history 中追溯。

---

## License

MIT — see [LICENSE](./LICENSE).
