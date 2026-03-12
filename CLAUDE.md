# a2a — AI Agent 快速上下文

> 本文件供 AI agent 首次进入项目时快速理解全局，人类开发者请看 README.md。

## 这是什么

a2a 是一个 **Claude Code skill**（不是独立应用），实现跨模型对抗式 code review。核心逻辑全在 `SKILL.md`，脚本只做辅助。

## 文件职责

| 文件 | 作用 | 什么时候改 |
|------|------|-----------|
| `SKILL.md` | skill 定义 + 完整执行流程，Claude Code 加载的入口 | 改流程、改 prompt、改 review 逻辑 |
| `scripts/preflight.sh` | 环境预检 + token bridge 缓存，结果缓存 15min | 改检测逻辑、加新 CLI 支持 |
| `scripts/a2a-health.sh` | 一键自检 + 自动修复 token bridge，人工排查用 | 改检测项、改修复逻辑 |
| `scripts/spinner.sh` | 终端动画，纯 UI | 基本不用动 |
| `references/review-lenses.md` | 三大审查视角定义（Challenger/Architect/Subtractor） | 调整审查标准 |
| `DEV.md` | 开发同步流程 + 版本号规则 | 流程变了才改 |

## 关键设计决策

1. **双向跨模型 dispatch**：Claude→Codex 走 `codex exec`；Codex→Claude 走 `claude -p` + token bridge（或从 Claude Code 内走 Agent tool sub-agent）。
2. **Token Bridge**：OAuth token 存在 macOS Keychain，Codex sandbox 无法直接访问。preflight 自动提取 token 缓存到 `~/.cache/a2a/.claude-token`（权限 600），Codex 通过 `ANTHROPIC_API_KEY` 环境变量传递。Step 1 每次自动检查补全，用户零操作。
3. **从 Claude Code 内不直接调 `claude -p`**：`CLAUDECODE=1` 环境变量触发 nested session 保护。Claude 侧 review 走 Agent tool。
4. **Reviewer 互不可见**：每个 reviewer 独立执行，看不到其他 reviewer 的输出，防止从众效应。
5. **Lean packet**：reviewer 只收到自己视角需要的 diff 切片 + 精简 intent，不传完整 plan 或项目规范。
6. **Red-line 统一扫描**：项目约束不传给 reviewer，由 Claude 在 Step 5 汇总时统一扫描一次。

## 修改注意事项

- 改完必须同步更新 `CHANGELOG.md` + `SKILL.md` 里的 version
- 同步到开源 repo 流程见 `DEV.md`
- Cache 路径：`~/.cache/a2a/`（preflight.json + .claude-token），调试时用 `preflight.sh --refresh` 或直接跑 `a2a-health.sh`
