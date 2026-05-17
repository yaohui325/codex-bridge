# Bundle 写入前 self-audit

每次调 `codex exec` 之前，逐条勾选。漏一条就停下来补全，不要凑合发。

## 内容完整性
- [ ] plan / 主件引用的所有文件，是否都 inline 到 `bundle/files/`？
- [ ] CLAUDE.md / AGENTS.md 关键约束，是否摘到 `request §4`？
- [ ] 对话里"已经试过 X / 排除了 Y / 确认 Z"，是否写到 `request §5`？
- [ ] 用户最终目标（不是当前任务），是否写到 `request §1`？

## conversation.md
- [ ] 最近 15 条人类↔Claude 交互是否完整蒸馏？（每条 1-3 行人话）
- [ ] 此前会话摘要 1 段是否包含？
- [ ] JSONL 路径是绝对路径，不是相对路径？

## Schema 与调用
- [ ] `response.schema.json` 是否就位在 bundle 目录（作为 prompt 里的结构参考，**不传给 CLI**）？
- [ ] `codex exec` **不传** `--output-schema`（codexapi 代理 502，已知不兼容）？
- [ ] `-o` 指向 bundle 里的 `response.json`？
- [ ] `--cd` 设了项目根的绝对路径？
- [ ] 用 stdin 传 prompt（`< "$BUNDLE/request.md"`），**不用** `"$(cat ...)"`？
- [ ] 加 `--skip-git-repo-check`（适用 greenfield，对 git 仓库也无害）？
- [ ] sandbox 模式选对？
  - plan-review = `read-only`
  - codify = `workspace-write`
  - review-iteration = `workspace-write`
  - verification-round = `read-only` (v1.1)

## 后处理（替代 CLI 协议层校验）
- [ ] 读 `response.json` 后用 `jq empty` 校验 JSON 合法？
- [ ] 用 `jq has(...)` 验证所有 schema required 字段存在？
- [ ] 用 `jq type/enum` 校验字段类型和 `key_findings[].type` 枚举值？
- [ ] codify / review-iteration 场景：用 git 或 mtime 快照校验 `files_changed` 真实？
- [ ] **plan-review 场景：检查 `key_findings[].dimension` 覆盖 4 类**（rationality / hidden_assumptions / conventions / scope_control）——任一类缺失视为审阅不充分，重跑或人工标注

## 多轮迭代
- [ ] Round > 1 时，request 是否引用并 inline 了前序轮次的 request / response / claude-review？
- [ ] **业务迭代**（codify / review-iteration）：Round = 2 是否是终轮？（不允许创建 `round-3/`）
- [ ] **审计 round**（plan-review 多轮）：见 [conventions.md](./conventions.md) 的 `purpose` 字段规则——manifest 必须含 `purpose` 标明本轮目的
- [ ] **验证 round**（v1.1 新增，`verification-round` scenario）：同样需 `manifest.purpose = "verify round-<N> extrapolations"`，validate-bundle.sh 用 purpose 豁免 max_rounds

## 安全
- [ ] bundle 路径中的特殊字符（空格、引号）是否在 shell 命令里正确转义？
- [ ] inline 的文件是否含 API key / token / 密码？（含则脱敏成 `<REDACTED>`）

## manifest.json
- [ ] `round`, `scenario`, `status`, `claude_session_jsonl` 全部填写？
- [ ] `bundle_dir` 是绝对路径？
- [ ] Round > 1 时 `previous_rounds` 数组列出了前序轮次的绝对路径？

## Pattern Extraction（v1.1 新增，强制纪律）

每次主轮 codex exec 跑完，**必须**过这一节（即使全部 finding 都判"无 pattern"，也要给理由）：

- [ ] 每条 accepted finding (`risk` / `hidden_assumption` / `disagreement`) 是否过了 pattern extraction 判断？
- [ ] 判定"无 pattern" 的 finding **每条**都有理由？
- [ ] 提取的每个 pattern 都给"为什么是 pattern" 理由？
- [ ] 如有 patterns，`extracted-patterns.md` 含搜索方法 + 横向查证结果？
- [ ] 如有 candidates，是否跑了 verification round（scenario=verification-round）？
- [ ] verification round 的 response.json 通过 7 步 jq 校验（**与主轮 8 步不同**，schema 不同）？
- [ ] 主轮 `extracted-patterns.md` 已更新"验证结果"段？
