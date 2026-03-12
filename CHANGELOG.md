# Changelog

## v1.8.0 — 2026-03-12
- **Token Bridge**：preflight 自动从 macOS Keychain 提取 OAuth access token 缓存到 `~/.cache/a2a/.claude-token`（权限 600），Codex sandbox 内通过 `ANTHROPIC_API_KEY` 环境变量传递给 `claude -p`，彻底打通 Codex→Claude 跨模型通道
- **双向跨模型 dispatch**：Claude→Codex 走 `codex exec`，Codex→Claude 走 `claude -p` + token bridge，从 Claude Code 发起时也可用 Agent tool sub-agent
- **代码作者检测**：Step 4 新增 author 判定（用户声明 > git metadata > 默认 Claude），按作者选择 dispatch 通道
- **Step 1 自动补全 token**：`/a2a` 启动时自动检测 token 文件，缺失则从 Keychain 提取，用户零手动操作
- **新增 `a2a-health.sh`**：一键自检 5 项（Skill 安装 / CLI 可用 / Auth 状态 / Token Bridge / 综合判定），token 缺失时自动修复，含实际 `claude -p` 调用测试
- preflight `_set_mode_flags` 重构：Claude ready 判定支持 token bridge fallback（auth=false 但 token 文件存在 → ready）
- 新增 `CLAUDE.md`：AI agent 进入项目的快速上下文
- README 新增 "Using a2a with AI Agents" 深度使用指南

## v1.7.0 — 2026-03-12
- 审查规模判定与 reviewer 配置调整
- 文档整理

## v1.6.0 — 2026-03-12
- `preflight.sh` 新增 TTL cache，默认复用 15 分钟本地检查结果，避免每次 `/a2a` 都重复探测环境
- 新增 `--refresh` 与 `--ttl-seconds N`，支持强制刷新和按次禁用缓存（`--ttl-seconds 0`）
- preflight 增加 best-effort 登录态检查，区分 CLI 已安装与登录缺失
- 修复 Codex 登录态字符串解析，避免 `not logged in` 被误判成已登录
- JSON 输出新增 `authenticated`、`cache`、`exit_code` 字段，便于上层复用
- 文档补充 preflight 只做本地环境/登录态检查，不会发起 review 请求

## v1.5.0 — 2026-03-12
- 恢复并明确 Plan Review：无代码 diff 但用户显式指定 plan / 设计文档时，也可以进入审查
- 收紧审查规模规则：按变更行数、新增代码量和目录跨度决定 reviewer 组合，不允许随意跳级
- review packet 改为按 lens 裁剪，项目 red-line 约束延后到 Claude 汇总阶段统一扫描

## v1.4.0 — 2026-03-11
- 新增前置 Gate：没有代码 diff 或只有 plan / 文档变更时，直接拒绝执行 a2a review
- 精简 review packet：plan 只提炼 1-2 句 intent，`CLAUDE.md` / `AGENT.md` 仅提取相关 red-line 约束
- 明确推荐工作流：`Plan -> 执行代码 -> a2a review`，把 review 固定在最后收口

## v1.3.0 — 2026-03-11
- 删除所有 ANSI 进度 printf，改用 emoji 标注关键节点
- 标题从 "Agent Clash" 改为 "a2a"
- 清理 SKILL.md 中所有 `agent-clash` 旧路径引用

## v1.2.1 — 2026-03-11
- `name` 改为 `a2a`，description 加全称 "Agent-to-Agent"
- 修复 spinner.sh 颜色变量：`'\033[...]'` → `$'\033[...]'`（单引号不解析转义）
- 更新 spinner.sh 路径注释

## v1.2.0 — 2026-03-11
- 修复 SKILL.md 中残留的 `mode: non-adversarial`，统一为 `single-model-multi-lens`
- 修复 codex dispatch：非 git 目录自动加 `--skip-git-repo-check`
- preflight.sh 完整重写：portable timeout（macOS 无 GNU timeout）+ python3 JSON 序列化
- 新增 spinner.sh：braille 字符动画，后台运行
- 新增 README.md（中英双语，MIT）
- 修复 codex symlink 指向错误

## v1.1.0 — 2026-03-10
- 目录从 `agent2agent-review` → `ac` → `agent-clash` → `a2a`
- `allowed-tools` 移除 `Edit`（skill 不修改代码）
- preflight.sh 加入 `--json` 模式输出

## v1.0.0 — 2026-03-09
- 初始版本：三大视角（Challenger / Architect / Subtractor）
- adversarial / single-model-multi-lens / blocked 三模式
- preflight.sh 基础版
