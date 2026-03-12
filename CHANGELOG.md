# Changelog

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
