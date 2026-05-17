# Bundle 命名 & 目录约定

## 位置

所有 bundle 都放在**项目工作目录**下：

```
<project-root>/.codex-bridge/
└── round-<n>/
```

- `<project-root>` = 用户当前工作目录的绝对路径
- `<n>` 从 1 开始，单调递增
- 每个 round 一个独立目录，互不覆盖

## Round 编号语义

`round` 字段有**三种**用法（v1.1 起），生产版必须明确区分：

| 用法 | 场景 | round 序列 | 说明 |
|---|---|---|---|
| **业务迭代** | `codify` → `review-iteration` | round-1 (codify) → round-2 (review-iteration) | 硬上限 2 轮，**第二轮后必须结束** |
| **审计 round** | 对 skill / plan 本身的多次 `plan-review` | round-1 → round-2 → round-N (均为 plan-review) | 没有硬上限；每轮 manifest **必须**含 `purpose` 字段 |
| **验证 round** (v1.1 新增) | 主轮 finding 提取出 patterns 后让 Codex 验证 candidates | round-N+1 (scenario=`verification-round`) | 每个主轮**最多跟 1 个验证轮**，**不递归**；manifest 必须含 `purpose = "verify round-<N> extrapolations"` |

**判定方式**：看 `manifest.purpose` + `manifest.scenario`：
- 存在 `purpose` 且 `scenario = plan-review` → 审计 round
- 存在 `purpose` 且 `scenario = verification-round` → 验证 round
- 不存在 `purpose` → 业务迭代 round，应受 `max_rounds` 限制

`scripts/create-bundle.sh` 默认创建业务迭代 round。审计 / 验证 round 需手动设置 `purpose` 字段。`scripts/validate-bundle.sh` 用 `purpose` 字段对 `plan-review` 或 `verification-round` 豁免 `round > max_rounds` 检查（业务迭代**不**豁免）。

## round-<n>/ 必含文件

| 文件 | 写入者 | 说明 |
|---|---|---|
| `manifest.json` | Claude Code | 元数据（场景、轮次、JSONL 路径、状态） |
| `request.md` | Claude Code | 主 prompt（填好模板的） |
| `files/` | Claude Code | inline 的所有相关文件副本 |
| `conversation.md` | Claude Code | 对话上下文蒸馏 |
| `response.schema.json` | Claude Code（从 templates 拷贝） | Codex 响应**结构参考**（不传 CLI，仅 prompt 引用 + Claude Code jq 后处理校验） |
| `response.json` | Codex 子进程 | Codex 按 prompt 描述结构返回的 JSON（Claude Code 用 jq 后处理校验，见 SKILL.md step 10）|
| `response.md` | Claude Code（运行后） | 人类可读渲染 |
| `extracted-patterns.md` (v1.1) | Claude Code（主轮 bundle 必填；验证轮 bundle 在 files/ 引用主轮的） | Pattern extraction 记录：每条 accepted finding 的 pattern 提取 / "无 pattern" 理由 + 横向查证结果 + 验证结果 |

## round-2/ 额外文件

| 文件 | 写入者 | 说明 |
|---|---|---|
| `claude-review.md` | Claude Code | 基于 round-1 的 review 意见 |

注意：`claude-review.md` 写在 **`round-1/`** 还是 `round-2/`？约定写在 **`round-1/`** 下（review 是对 round-1 的反馈），然后在 round-2/request.md 里 inline 进来。

## manifest.json 字段

```json
{
  "round": 1,
  "max_rounds": 2,
  "scenario": "plan-review | codify | review-iteration | verification-round",
  "status": "pending | in-progress | completed | failed",
  "claude_session_jsonl": "/Users/<user>/.claude/projects/<encoded>/<uuid>.jsonl",
  "previous_rounds": [],
  "created_at": "<ISO-8601 timestamp>",
  "bundle_dir": "<absolute-path-to-this-round>",
  "codex_command": "<the actual shell command run, for audit>",
  "codex_exit_code": null
}
```

`status` 流转（**best-effort**——由 Claude Code 在 codex 调用前后更新；用 `scripts/` 自动化更可靠）：

```
pending →（创建 bundle 完成）→ in-progress →（codex 退出）→ completed | failed
```

⚠️ **重要**：没有事务保证，状态字段可能停留在中间态（例如 codex 被强制中断、Claude Code 退出）。**建议**：
- 用 `scripts/create-bundle.sh` 自动初始化 manifest（避免漏字段）
- 把 manifest 视为**审计快照**（记录意图与命令），用 `response.json` 是否存在 + 是否合法 JSON 判定**真实**完成状态
- 不要把 `manifest.status` 当作硬保证去做关键决策（例如自动触发 Round 2 之前，应该看 response.json 而不是只看 status="completed"）

## bundle/files/ 命名

inline 文件副本的命名：路径里的 `/` 替换为 `__`（双下划线），保留扩展名。

例：
- `src/utils/helpers.ts` → `bundle/files/src__utils__helpers.ts`
- `plan.md` → `bundle/files/plan.md`
- `app/api/route.ts` → `bundle/files/app__api__route.ts`

保留路径信息、避免子目录嵌套，方便 Codex 一眼看清。

## Git ignore

建议把 `.codex-bridge/` 加到项目 `.gitignore`：

```
# Codex Bridge runtime artifacts
.codex-bridge/
```

bundle 本身留作本地审计 / 复盘记录，不入版本控制。

## 多 round 引用规则

Round 2 的 `request.md` 必须：

1. 在元数据里列前序：
   ```
   - Round 1 bundle: <absolute-path-to-round-1>
   - Round 1 request: <round-1>/request.md
   - Round 1 response: <round-1>/response.json
   - Round 1 Claude review: <round-1>/claude-review.md
   ```

2. **完整 inline** 上述 3 个文件的内容到 round-2/request.md 内（不依赖 Codex 跨目录读，简化推理）。

## 路径中的空格处理

项目根可能含空格（如 `/Users/xueyaohuigeren/hezuo -skill`）。处理规则：

- Bash 命令里所有路径用双引号包裹：`"<bundle>/request.md"`
- `codex exec --cd "<path>"` 必须有引号
- JSONL 路径同样
