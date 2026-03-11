---
name: a2a
version: "1.4.0"
description: "a2a (Agent-to-Agent) — 跨模型对抗式 code review。Claude 写的代码让 Codex 审，Codex 写的让 Claude 审，互相找茬不留死角。"
argument-hint: '要审查的文件路径、PR 编号或 git diff 范围'
allowed-tools: Read, Write, Bash, Grep, Glob, Agent, AskUserQuestion
---

# a2a — 对抗式 Code Review

> 谁写的代码，就让对手来审。Self-review is self-deception.

## 核心机制

**对抗原则**：review 优先在**对立模型**上执行。Claude 产出的代码由 Codex 审查，Codex 产出的代码由 Claude 审查。

**为什么有效**：不同模型有不同的 blind spot。Claude 倾向 over-engineer，Codex 倾向跳过 boundary check。让它们互相找茬，bug 无处藏身。

### 运行模式

根据 preflight 结果自动选择：

| 模式 | 条件 | 说明 |
|------|------|------|
| **adversarial** | Claude + Codex 均可用 | 跨模型对抗审查，最高质量 |
| **single-model-multi-lens** | 仅一个 CLI 可用 | 同模型多视角审查（通过 Agent tool spawn 独立 agent），质量降低但仍有多视角覆盖 |
| **blocked** | 无 CLI 可用 | 无法执行 review，报告标注 `mode: blocked` 并中止 |

报告中 `Mode` 字段必须如实标注当前模式。

## 触发方式

- 用户说 "review"、"审查"、"code review"、"帮我 review 一下"
- 用户说 "a2a"、"a2a review"、"对抗审查"
- plan-to-codex 的 Phase 3 收口环节
- 手动指定：`/a2a src/path/to/file.js`

## 审查规模判定

先算变更量，再决定派几个 reviewer：

| 规模 | 行数 | Reviewer 配置 | 预估耗时 |
|------|------|--------------|---------|
| **Light** | < 50 | 1 人（Challenger） | ~30s |
| **Medium** | 50–200 | 2 人（Challenger + Architect） | ~1min |
| **Heavy** | 200+ | 3 人全上 | ~2min |
| **Cross-module** | 涉及 3+ 目录 | 3 人 + red-line scan | ~3min |

## 三大审查视角

详见 `references/review-lenses.md`。

- **The Challenger — 质疑者**：找 edge case、未处理的 error path、race condition
- **The Architect — 架构师**：审视 coupling、职责边界、component 拆分合理性
- **The Subtractor — 删减者**：找 over-engineering、premature abstraction、多余 config

## Preflight — 环境检测

首次使用或分享给同事时，跑 preflight 确认环境就绪：

```bash
~/.claude/skills/a2a/scripts/preflight.sh
# JSON 格式（供脚本读取）：
~/.claude/skills/a2a/scripts/preflight.sh --json
```

检测项：Claude CLI、Codex CLI。两个 CLI 都有才能真正跨模型对抗。

## 前置校验（Gate）

**a2a 只审代码变更，不审 Plan / 文档草案。**

执行前必须确认存在可审查的代码变更：
1. `git diff --stat` 或用户指定的文件有**实际代码修改**
2. 如果只有 plan、TODO、纯文档变更 → **拒绝执行**，提示：`"没有检测到代码变更。请先完成编码再运行 a2a review。"`
3. 如果用户在 Plan 阶段就调用 a2a → 同样拒绝，建议流程：`Plan → 执行 → a2a review`

## 执行流程

### Step 1: 环境检测 + 确定变更范围

> 🔍 运行 preflight，确认模式，确定审查范围

```bash
~/.claude/skills/a2a/scripts/preflight.sh --json
```

确定变更范围（必须是代码文件的 diff，不是 plan 文档）：
```bash
# 自动检测
git diff --stat HEAD~1
# 指定范围
git diff --stat main...HEAD
# 指定文件
cat src/pages/target.vue
```

如果 diff 为空或仅包含 .md 文件 → 触发 Gate 拒绝。

### Step 2: 加载审查基准

> 📋 读取以下文件建立 review context

1. `references/review-lenses.md` — 三大视角定义
2. 目标项目的 `AGENT.md` / `AGENTS.md`（如存在）— 编码规范与 red line
3. 目标项目的 `.ai/constraints.json`（如存在）— 硬约束

### Step 3: 明确变更意图

**必须在 review 前声明**：这次改动要解决什么问题？

```
Intent:     {一句话描述这次改动的目的}
Constraint: {这次改动不能碰的东西}
```

### Step 4: 派遣 Reviewer（并行）

> 🤖 跨模型执行，必须使用对立模型

**非 git 目录检测**（dispatch 前必须执行）：
```bash
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  SKIP_GIT_FLAG=""
else
  SKIP_GIT_FLAG="--skip-git-repo-check"
fi
```

如果当前是 Claude 环境：
```bash
codex exec --cd "$(pwd)" $SKIP_GIT_FLAG --full-auto -- "按照以下审查清单 review 代码变更..."
```
- `--cd` 确保 Codex 在正确的项目目录下执行
- `--skip-git-repo-check` 用于非 git 目录（自动检测，按需添加）
- `--` separator 防止 prompt 内容被误解析为 flag
- **禁止传 `--model` 参数**——让 Codex 使用用户自己在 `~/.codex/config.toml` 配置的模型

如果当前是 Codex 环境：
```bash
claude -p "按照以下审查清单 review 代码变更..."
```

每个 reviewer 收到统一的 **review packet**（严格精简）：
- **变更 intent**：1-2 句话概括目的，**不传原始 plan 全文**
- **审查视角定义**：只给自己那个 lens（从 review-lenses.md 摘取对应段落）
- **完整 diff**：代码变更（这是唯一可以长的部分）
- **项目 red-line 约束**：仅相关条目，不是整个 CLAUDE.md

**Packet 精简规则**：
- Plan / 设计文档 → 提炼为 1-2 句 intent，不传原文
- CLAUDE.md / AGENT.md → 只提取代码红线和安全约束，跳过流程/协作类规则
- 如果 diff 超过 500 行 → 按文件拆分，每个 reviewer 只审自己 lens 最相关的文件

所有 reviewer **并行执行**，互不可见对方结果（防止从众效应）。

### Step 5: 汇总 Findings

> 📊 收集所有 reviewer 发现，保留 reviewer provenance，按 severity 分级

| Severity | 定义 | 示例 |
|----------|------|------|
| **🔴 High** | 会导致线上问题或数据丢失 | 未处理的 null、XSS injection、state race |
| **🟡 Medium** | 不影响当前功能但埋坑 | coupling 过紧、缺少 error boundary、hardcode |
| **🟢 Low** | 风格或可维护性建议 | 命名不清、注释缺失、可简化 |

主审裁定每条 finding：
- **Accept** — 确实是问题，需要修
- **Dismiss** — reviewer 过度解读或不适用当前场景
- **Flag** — 有道理但 non-blocking，记录为 TODO

### Step 6: 输出 Verdict Report

```markdown
## a2a Review — {PACK_ID}

**变更**: {简述}
**规模**: {Light / Medium / Heavy}
**Reviewers**: {Challenger / Architect / Subtractor}
**执行模型**: {Claude ↔ Codex}
**Mode**: {adversarial / single-model-multi-lens / blocked}

### Verdict: {PASS / CONTESTED / REJECT / BLOCKED}

### Findings

| # | Severity | Lens | File:Line | 问题 | 建议 | 裁定 |
|---|----------|------|-----------|------|------|------|
| 1 | 🔴 | Challenger | src/x.vue:42 | ... | ... | Accept |
| 2 | 🟡 | Architect | src/y.js:18 | ... | ... | Dismiss: 理由 |

### 总结
{一段话总结 review 结论和 next step}
```

## Verdict 标准

| Verdict | 条件 |
|---------|------|
| **PASS** | 无 🔴 High finding |
| **CONTESTED** | 有 🔴 但 reviewer 之间存在分歧 |
| **REJECT** | 多个 reviewer 共识性 🔴 finding |
| **BLOCKED** | 环境检测失败，无可用 CLI，review 无法执行 |

## 与 plan-to-codex 集成

本 skill 可以作为 plan-to-codex Phase 3 的**增强版收口 review**：

```
原 Phase 3 流程:
  Claude 首审 → seal_review.sh → Codex 收口

增强流程:
  Claude 首审 → a2a review（多视角对抗） → verdict → review.md
```

当 a2a verdict 为 PASS 时，可以跳过 `seal_review.sh`。

## 项目规范自动适配

审查时自动检测目标项目根目录的以下文件（任一存在即读取）：
- `AGENT.md` / `AGENTS.md` — 编码规范与 red line
- `CLAUDE.md` — Claude 专属约束
- `.ai/constraints.json` — 硬约束

**无需 hardcode 项目规则**——每个项目自带自己的标准，reviewer 自动遵守。

## Fallback: Single-Model-Multi-Lens 模式

当仅有一个 CLI 可用时（比如没装 Codex）：
- 通过 Agent tool spawn 独立 agent 执行多视角审查（每个 agent 独立运行，不共享上下文）
- 报告标注 `mode: single-model-multi-lens`
- 质量低于跨模型对抗，但仍提供多视角覆盖

当无 CLI 可用时：
- 报告标注 `mode: blocked`，verdict 为 **BLOCKED**，中止 review

## 注意事项

- 本 skill 只产出 **verdict report**，不自动改代码
- Reviewer 不能看到彼此的输出（防止 conformity bias）
- 每条 finding 必须引用**具体文件和行号**，不接受泛泛而谈
