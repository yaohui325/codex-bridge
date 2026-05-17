# Claude Code 会话 JSONL 结构指南

每个 Claude Code 会话被存为一个 JSONL 文件，是 `conversation.md` 深读层的真相源。Codex 不熟此格式，所以本指南内容应该被 inline 到每份 `conversation.md` 的"深度参考"节，让 Codex 知道怎么读。

## 文件位置

```
~/.claude/projects/<encoded-cwd>/<session-uuid>.jsonl
```

**路径编码规则**：当前工作目录的绝对路径，做两步替换：
1. `/` → `-`
2. 空格 → `--`

例：
- `/Users/xueyaohuigeren/hezuo -skill` → `-Users-xueyaohuigeren-hezuo--skill`
- `/Users/foo/bar baz` → `-Users-foo-bar--baz`

## 每行格式

每行一个 JSON object，**必含** `type` 字段。

## 关键 type 取值

| type | 含义 |
|---|---|
| `user` | 用户消息 |
| `assistant` | Claude 助手回复 |
| `tool_use` | Claude 调用工具 |
| `tool_result` | 工具返回结果 |
| `attachment` | hook 输出、文件上传等附件 |
| `last-prompt` | 会话尾标记 |
| `permission-mode` | 当前权限模式（plan / acceptEdits 等） |

其他 type（如 `summary`、`compact-summary`）一般用作压缩分隔，可忽略。

## 抽取人类↔Claude 干净对话

只看人话和 Claude 回复：

```bash
jq -c 'select(.type=="user" or .type=="assistant")' \
  ~/.claude/projects/<encoded>/<uuid>.jsonl
```

抽最近 50 条：

```bash
jq -c 'select(.type=="user" or .type=="assistant")' \
  ~/.claude/projects/<encoded>/<uuid>.jsonl | tail -50
```

## 嵌套字段

- `.message.content` 通常是结构化数组，包含 `text` / `tool_use` / `tool_result` 等块
- 提取纯文本：
  ```bash
  jq -r '.message.content[] | select(.type=="text") | .text'
  ```
- 看用户原始 prompt：
  ```bash
  jq -r 'select(.type=="user") | .message.content // .message' <jsonl> | tail -30
  ```

## 在 bundle 里的推荐用法

`conversation.md` 三层结构：

1. **顶部（必看）**：Claude Code 手动蒸馏的最近 15 条人话总结
2. **中部（必看）**：此前会话摘要 1 段
3. **底部（按需深读）**：JSONL 绝对路径 + 抽取命令示例

Codex 如果觉得蒸馏不够、想看原始对话，可以自己用 jq 抽。多数场景顶部+中部足够。

## Sandbox 下访问 JSONL 的验证

`codex exec --sandbox read-only` 限制 Codex 子进程的文件访问范围。`~/.claude/projects/...jsonl` 在**用户家目录**下——在某些 sandbox 配置下可能**不可读**。

**Claude Code 在写完 `conversation.md` 之后，必须做 sandbox 可读性验证**：

### 1. 测试 Codex 是否能读 JSONL

```bash
echo "请读取 $JSONL_PATH 的第 1 行并复述其 type 字段值" | codex exec \
  --cd "$PROJECT_ROOT" --sandbox read-only --skip-git-repo-check
```

### 2. 判定与降级

- **能读到** → 三层架构完整，JSONL 深读层可用，conversation.md 顶部蒸馏就够
- **报错（permission denied / no such file）** → 三层退化为两层。**必须**把 JSONL 抽取后的关键摘要直接 **inline** 到 `conversation.md`，不再依赖 Codex 自行读取：

  ```bash
  echo "" >> "$BUNDLE/conversation.md"
  echo "## 附录：JSONL 关键抽取（sandbox 不可读时的 inline）" >> "$BUNDLE/conversation.md"
  echo '```' >> "$BUNDLE/conversation.md"
  jq -c 'select(.type=="user" or .type=="assistant") | {type, text: (.message.content[]? | select(.type=="text") | .text) // .message.content // .message}' \
    "$JSONL_PATH" | tail -100 >> "$BUNDLE/conversation.md"
  echo '```' >> "$BUNDLE/conversation.md"
  ```

### 3. 实践建议：默认就 inline

为了避免运行时分支，**默认**就把"最近 50-100 条" JSONL 抽取片段 inline 到 `conversation.md` 底部。这样不管 sandbox 怎么配置都能用。Codex 仍可按需读完整 JSONL，但不依赖它。
