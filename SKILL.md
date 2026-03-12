---
name: a2a
version: "1.8.0"
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

| 模式 | 条件 | 说明 |
|------|------|------|
| **adversarial** | Claude + Codex 双向均可用 | 跨模型对抗审查，最高质量 |
| **single-model-multi-lens** | 仅一侧可用 | 同模型多视角审查，质量降低但仍有多视角覆盖 |
| **blocked** | 无法执行 | 无法执行 review，报告标注 `mode: blocked` 并中止 |

**跨模型双向 dispatch**：
- **Claude 写的代码 → Codex 审**：`codex exec`（Codex 有自己的 API key）
- **Codex 写的代码 → Claude 审**：`claude -p` + **token bridge**（见下方说明）

**Token Bridge 机制**（解决 Codex sandbox 无法访问 macOS Keychain 的问题）：

preflight 在有 Keychain 访问权限的环境中（如 Claude Code、正常终端）运行时，会自动提取 OAuth access token 并缓存到 `~/.cache/a2a/.claude-token`（权限 600）。Codex sandbox 内调 `claude -p` 时，通过读取此文件设置 `ANTHROPIC_API_KEY` 环境变量，绕过 Keychain 限制。

```bash
# Codex 环境内调 Claude 的标准方式：
TOKEN=$(cat ~/.cache/a2a/.claude-token 2>/dev/null)
ANTHROPIC_API_KEY="$TOKEN" claude -p "review prompt..."
```

> ⚠️ **从 Claude Code 内部不要直接调 `claude -p`**：`CLAUDECODE=1` 环境变量会触发 nested session 保护。如需从 Claude 侧 review，使用 Agent tool spawn sub-agent。

报告中 `Mode` 字段必须如实标注当前模式。

## 触发方式

- 用户说 "review"、"审查"、"code review"、"帮我 review 一下"
- 用户说 "a2a"、"a2a review"、"对抗审查"
- plan-to-codex 的 Phase 3 收口环节
- 手动指定：`/a2a src/path/to/file.js`

## 审查规模判定

先算变更量，再决定派几个 reviewer。**必须严格遵守，不得跳级。**

```bash
# 硬性检查（dispatch 前执行）
diff_lines=$(git diff --stat HEAD~1 | tail -1 | grep -oE '[0-9]+' | head -1)
new_lines=$(git diff HEAD~1 --diff-filter=A --stat | tail -1 | grep -oE '[0-9]+' | head -1)
dir_count=$(git diff --name-only HEAD~1 | xargs -I{} dirname {} | sort -u | wc -l)
```

| 规模 | 条件 | Reviewer 配置 | 预估耗时 |
|------|------|--------------|---------|
| **Light** | < 50 行 | Challenger only | ~30s |
| **Medium** | 50–200 行 | Challenger + Architect | ~1min |
| **Heavy** | 200+ 行，新增 ≤ 100 行 | Challenger + Architect | ~1.5min |
| **Heavy+** | 200+ 行，新增 > 100 行 | 三人全上 | ~2min |
| **Cross-module** | 涉及 3+ 目录 | 三人全上 | ~2min |

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
# 登录状态刚变化时强制刷新：
~/.claude/skills/a2a/scripts/preflight.sh --refresh
```

检测项：Claude CLI、Codex CLI、本地登录态。默认缓存 900 秒，只做本地检查，不会发起 review 请求。

## 前置校验（Gate）

a2a 支持审查**代码变更**和**Plan / 设计方案**，自动判定模式：

1. **Code Review 模式**：`git diff --stat` 或用户指定的文件有实际代码修改 → 进入代码审查
2. **Plan Review 模式**：无 diff，但用户明确指定了 plan / 设计文档 → 进入 Plan 审查
3. **无审查对象**：无 diff 也无用户指定 → 提示：`"未检测到审查对象。请指定代码变更范围或要审查的 plan 文件。"`

## 执行流程

### Step 1: 环境检测 + 确定变更范围

> 🔍 运行 preflight，确认模式，确定审查范围。**Token bridge 会自动维护，无需手动操作。**

```bash
~/.claude/skills/a2a/scripts/preflight.sh --json
```

如果刚执行过 `codex login` / `claude auth login`，用 `--json --refresh` 跳过缓存。

**Token bridge 自动补全**：preflight 完成后，检查 token 文件是否存在。如果缺失，立即自动补全：
```bash
TOKEN_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/a2a/.claude-token"
if [[ ! -s "$TOKEN_FILE" && "$(uname)" == "Darwin" ]]; then
  security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
    | python3 -c "import json,sys; t=json.load(sys.stdin).get('claudeAiOauth',{}).get('accessToken',''); print(t) if t else None" \
    > "$TOKEN_FILE" 2>/dev/null && chmod 600 "$TOKEN_FILE"
fi
```
这段在每次 `/a2a` 启动时自动执行，用户完全无感。

确定变更范围：
```bash
# 自动检测
git diff --stat HEAD~1
# 指定范围
git diff --stat main...HEAD
# 指定文件
cat src/pages/target.vue
```

根据 Gate 规则判定模式：有 diff → Code Review；无 diff 但有 plan → Plan Review；否则拒绝。

### Step 2: 加载审查基准

> 📋 读取视角定义（red-line 扫描延迟到 Step 5 统一执行）

1. `references/review-lenses.md` — 三大视角定义
2. 目标项目的 `AGENT.md` / `AGENTS.md`（如存在）— 仅用于理解项目 context，**不传给 reviewer**
3. 目标项目的 `.ai/constraints.json`（如存在）— 同上，留给 Step 5 统一扫描

### Step 3: 明确变更意图

**必须在 review 前声明**：这次改动要解决什么问题？

```
Intent:     {一句话描述这次改动的目的}
Constraint: {这次改动不能碰的东西}
```

### Step 4: 派遣 Reviewer（并行）

> 🤖 Claude 始终是 orchestrator，双向跨模型通过不同 dispatch 通道实现

**非 git 目录检测**（dispatch 前必须执行）：
```bash
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  SKIP_GIT_FLAG=""
else
  SKIP_GIT_FLAG="--skip-git-repo-check"
fi
```

**Step 4a: 判定代码作者**

根据以下信号判定变更代码的作者模型：
1. 用户明确告知（"这是 Codex 写的"、"刚用 Codex 生成的"）
2. Git commit message 含 `codex`、`openai` 等关键词
3. 默认：假定为 Claude 产出（因为 a2a 从 Claude Code 发起，大多数场景是 Claude 刚写完代码后 review）

**Step 4b: 按作者 + 当前环境选择 dispatch 通道**

#### 路径 A: Claude 产出 → Codex 审查（从 Claude Code 发起）

```bash
codex exec --cd "$(pwd)" $SKIP_GIT_FLAG --full-auto -- "按照以下审查清单 review 代码变更..."
```
- `--cd` 确保 Codex 在正确的项目目录下执行
- `--skip-git-repo-check` 用于非 git 目录（自动检测，按需添加）
- `--` separator 防止 prompt 内容被误解析为 flag
- **禁止传 `--model` 参数**——让 Codex 使用用户自己在 `~/.codex/config.toml` 配置的模型

#### 路径 B: Codex 产出 → Claude 审查（从 Claude Code 发起）

通过 **Agent tool** spawn 隔离 sub-agent 执行 review（in-process，天然有 auth）：

```
使用 Agent tool，为每个 lens 分别 spawn 一个独立 agent：
- agent 1: Challenger lens + 完整 diff
- agent 2: Architect lens + 文件列表/签名/摘要
- agent 3: Subtractor lens + 完整 diff + 新增文件

每个 agent 独立执行，互不可见（满足隔离要求）。
```

#### 路径 C: Codex 产出 → Claude 审查（从 Codex 发起，token bridge）

当 a2a 从 Codex 环境发起时，通过 **token bridge** 调用 `claude -p`：

```bash
# 读取 preflight 缓存的 OAuth token
TOKEN=$(cat ~/.cache/a2a/.claude-token 2>/dev/null)
if [[ -z "$TOKEN" ]]; then
  echo "错误：未找到 Claude token 缓存。请先在 Claude Code 或终端中运行："
  echo "  ~/.claude/skills/a2a/scripts/preflight.sh --refresh"
  exit 1
fi

# 通过环境变量传递 token，绕过 Keychain 限制
ANTHROPIC_API_KEY="$TOKEN" claude -p "按照以下审查清单 review 代码变更..."
```

> **前提**：必须至少运行过一次 `preflight.sh`（从 Claude Code 或正常终端，非 Codex sandbox），以便将 OAuth token 从 macOS Keychain 缓存到文件。

#### 路径 D: Codex 不可用 → Claude 单模型多视角（降级）

同路径 B 的 Agent tool 方式，但报告标注 `mode: single-model-multi-lens`。

每个 reviewer 收到**专属 review packet**（按 lens 裁剪，严格精简）：

**通用字段**（所有 reviewer 共享）：
- **变更 intent**：1-2 句话概括目的，**不传原始 plan 全文**
- **审查视角定义**：只给自己那个 lens（从 review-lenses.md 摘取对应段落）

**Lens 专属 diff 裁剪**：
| Lens | 收到的 diff 内容 |
|------|----------------|
| **Challenger** | 完整 diff（需要看具体代码找 bug） |
| **Architect** | 文件列表 + 函数签名 + 变更摘要（审结构不需要逐行） |
| **Subtractor** | 完整 diff + 新增文件列表（找多余代码） |

**不传给 reviewer 的内容**：
- ~~项目 red-line 约束~~ → 移到 Step 5 由 Claude 统一扫描
- ~~CLAUDE.md / AGENT.md~~ → 不传给 reviewer
- Plan / 设计文档 → 提炼为 1-2 句 intent，不传原文

**Reviewer 输出限制**（必须附加到每个 reviewer 的 prompt 末尾）：
```
输出限制：
- 每条 finding ≤ 3 行（trigger + impact + fix）
- 总 findings ≤ 10 条
- 无 finding 时只输出 "LGTM"，不要写分析过程
```

所有 reviewer **并行执行**，互不可见对方结果（防止从众效应）。

### Step 5: 汇总 Findings + Red-Line Scan

> 📊 收集所有 reviewer 发现，**然后 Claude 统一执行一次 red-line scan**

**Red-Line Scan**（仅在此步骤执行一次）：
1. 读取项目的 `AGENT.md`、`CLAUDE.md`、`.ai/constraints.json`
2. 提取 red-line 约束条目
3. 对完整 diff 扫描一次，违规项作为 🔴 High finding 加入汇总

通用 red line（项目无配置时的兜底）：
```
eval() / new Function() / innerHTML =   → security risk
未经封装的 process.env 直接读取          → environment leak
硬编码 secret / token                   → credential exposure
```

**汇总规则**：保留 reviewer provenance，按 severity 分级

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

**表格自适应规则**：根据 findings 数量和内容长度选择宽/窄模式。

**固定 5 列**：`#`, `Sev`, `Lens`, `问题`, `裁定`

| 字段 | 规则 |
|------|------|
| **Sev** | 只写 emoji：🔴🟡🟢，不加文字 |
| **Lens** | 缩写：`Ch` = Challenger, `Ar` = Architect, `Su` = Subtractor；多人 `Ch+Ar` |
| **问题** | `` `file:line` `` 嵌在开头，后接完整问题描述，**不省略内容** |
| **裁定** | 自适应（见下方宽窄规则） |

**宽模式**（≤ 5 条 findings 或问题描述普遍短）：
- 裁定列写完整：`Accept — 理由说明`、`Dismiss — 为什么不适用`、`Flag — 记 TODO 的原因`

**窄模式**（≥ 6 条 findings 或问题描述普遍长）：
- 裁定列只写结果：`Accept`、`Dismiss`、`Flag`
- 原因移到表格下方的 **裁定说明** 区（仅列出需要解释的条目）：
  ```
  **裁定说明**
  - #2 Dismiss: reviewer 过度解读，当前 scope 只服务 content agent
  - #6 Flag: non-blocking，记 TODO，后续按 attempt 编号落盘
  ```

```markdown
## a2a Review — {PACK_ID}

**变更**: {简述}
**规模**: {Light / Medium / Heavy / Heavy+}
**Reviewers**: Challenger + Architect + Subtractor
**Mode**: {adversarial / single-model-multi-lens / blocked}

### Verdict: {PASS / CONTESTED / REJECT / BLOCKED}

### Findings

| # | Sev | Lens | 问题 | 裁定 |
|---|-----|------|------|------|
| 1 | 🔴 | Ch | `src/x.vue:42` 删除"敏感操作确认"不安全 — 权限可被放宽，删了没第二道门 | Accept — 保留最小版 |
| 2 | 🟡 | Ar | `src/y.js:18` TODO 放在 wiki 目录语义不对 — wiki 是知识沉淀不是看板 | Accept — 移到根目录 |
| 3 | 🟢 | Su | `lib/z.ts:5` 单文件 Markdown 不支持并发检索 | Dismiss |

**裁定说明**
- #3 Dismiss: 当前 <15 条 TODO，过早优化

### 总结
{一段话总结 review 结论和 next step}
```

**底线**：问题列永远不省略。裁定列可以压缩但原因不能丢（移到下方）。

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

审查时自动检测目标项目根目录的以下文件（任一存在即读取），**仅在 Step 5 统一扫描时使用**：
- `AGENT.md` / `AGENTS.md` — 编码规范与 red line
- `CLAUDE.md` — Claude 专属约束
- `.ai/constraints.json` — 硬约束

**无需 hardcode 项目规则**——每个项目自带自己的标准，Step 5 统一检查。

## Dispatch 通道总结

| 发起环境 | 代码作者 | Reviewer | Dispatch 通道 | 模式 |
|---------|---------|----------|-------------|------|
| Claude Code | Claude | Codex | `codex exec` | adversarial |
| Claude Code | Codex | Claude | Agent tool (sub-agent) | adversarial |
| Codex | Codex | Claude | `claude -p` + token bridge | adversarial |
| 任意 | 任意 | 同模型 | Agent tool 或 Codex 自审 | single-model-multi-lens |

**Token Bridge**：preflight 从 macOS Keychain 提取 OAuth token → 缓存到 `~/.cache/a2a/.claude-token`（权限 600） → Codex sandbox 内通过 `ANTHROPIC_API_KEY` 环境变量传递给 `claude -p`。

## Fallback: Single-Model-Multi-Lens 模式

当 Codex CLI 不可用时（没装或 auth 失败）：
- 所有 reviewer 通过 Agent tool spawn 独立 sub-agent 执行（每个 agent 独立运行，不共享上下文）
- 报告标注 `mode: single-model-multi-lens`
- 质量低于跨模型对抗，但仍提供多视角覆盖

## 注意事项

- 本 skill 只产出 **verdict report**，不自动改代码
- Reviewer 不能看到彼此的输出（防止 conformity bias）
- 每条 finding 必须引用**具体文件和行号**，不接受泛泛而谈
- **禁止使用 `claude -p` 做 reviewer dispatch**（见运行模式部分说明）
