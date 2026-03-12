# agent-2-agent (a2a)

> Cross-model adversarial code review for Claude Code.
> 跨模型对抗式 code review — 谁写的代码，就让对手来审。

**Self-review is self-deception.** Claude-written code gets reviewed by Codex; Codex-written code gets reviewed by Claude. Different models have different blind spots — let them fight.

---

## Quick Start

```bash
# 1. Clone and install
git clone git@github.com:CtriXin/agent-2-agent.git
cp -r agent-2-agent ~/.claude/skills/a2a

# 2. Check environment
~/.claude/skills/a2a/scripts/preflight.sh

# 3. Use in Claude Code
/a2a src/path/to/file.js
```

## Requirements

| Tool | Required | Purpose |
|------|----------|---------|
| [Claude Code](https://claude.ai/code) | ✅ | Orchestrator + lead reviewer |
| [OpenAI Codex CLI](https://github.com/openai/codex) | ✅ for adversarial mode | Cross-model reviewer |
| python3 | ✅ | Safe JSON output in preflight |
| jq | optional | Prettier preflight output |

Install Codex CLI:
```bash
npm install -g @openai/codex
```

## How It Works

```
Prepare a code diff or explicitly point a2a at a plan/design doc
       ↓
a2a determines the review target
       ↓
Code diff => code review
Explicit plan doc => plan review
No target => refuse to run
       ↓
Claude extracts a short intent and picks reviewers by scale
       ↓
Claude dispatches Codex reviewers in parallel ──┐
  - The Challenger: finds edge cases & error paths  │
  - The Architect:  questions design decisions       │ (codex)
  - The Subtractor: removes unnecessary code        ─┘
       ↓
Claude aggregates findings (preserving reviewer provenance)
       ↓
Verdict: PASS / CONTESTED / REJECT / BLOCKED
```

## Review Gate

a2a supports two entry modes:

- Code review: if there is a real code diff, a2a reviews the code.
- Plan review: if there is no diff but the user explicitly points to a plan/design doc, a2a reviews the plan.
- No target: if there is neither a diff nor an explicit target file, a2a refuses to run.

## Lean Review Packet

Each reviewer receives a deliberately small, lens-specific packet:

- Intent distilled into 1-2 sentences instead of the full plan
- Only the assigned review lens
- Only the diff slice that reviewer actually needs
- Project red-line constraints are scanned once by Claude during aggregation, not copied into every reviewer packet

This keeps reviewers focused on the review target instead of wasting context on long planning documents or duplicated policy text.

## Review Modes

| Mode | Condition | Quality |
|------|-----------|---------|
| `adversarial` | Claude + Codex both available | ⭐⭐⭐ Best |
| `single-model-multi-lens` | Only one CLI available | ⭐⭐ Good |
| `blocked` | No CLI available | ❌ Cannot run |

## Three Review Lenses

Defined in `references/review-lenses.md`:

- **The Challenger** — "Prove to me this won't break." Finds edge cases, unhandled error paths, race conditions.
- **The Architect** — "Will this design survive requirement changes?" Reviews coupling, boundaries, component responsibility.
- **The Subtractor** — "What happens if this code disappears?" Finds over-engineering, premature abstraction, unnecessary config.

## Verdict Report Format

```markdown
## a2a Review — {ID}

**Change**: {description}
**Scale**: Light | Medium | Heavy | Cross-module
**Mode**: adversarial | single-model-multi-lens | blocked

### Verdict: PASS | CONTESTED | REJECT | BLOCKED

| # | Severity | Lens | File:Line | Issue | Suggestion | Decision |
|---|----------|------|-----------|-------|------------|----------|
| 1 | 🔴 High  | Challenger | src/x.vue:42 | ... | ... | Accept |
| 2 | 🟡 Medium | Architect | src/y.js:18 | ... | ... | Dismiss: reason |
```

## File Structure

```
a2a/
├── SKILL.md                    # Claude Code skill definition (the brain)
├── README.md                   # This file
├── references/
│   └── review-lenses.md        # Challenger / Architect / Subtractor definitions
└── scripts/
    ├── preflight.sh            # Environment check (exit 0=READY, 2=PARTIAL, 3=MISSING)
    └── spinner.sh              # Animated progress indicator (terminal users)
```

## Preflight Exit Codes

```
0  READY    — Claude + Codex both available, adversarial mode ready
2  PARTIAL  — Only one CLI, single-model-multi-lens mode
3  MISSING  — No CLI available, blocked
64 USAGE    — Bad arguments
```

---

## 中文说明

**agent-2-agent (a2a)** 是一个 Claude Code skill，实现跨模型对抗式 code review。

**核心原则**：Claude 写的代码让 Codex 审，Codex 写的让 Claude 审。不同模型有不同盲区——让它们互相找茬，bug 无处藏身。

**安装**：clone 本 repo，把 `agent-2-agent/` 目录复制到 `~/.claude/skills/a2a`，重启 Claude Code，输入 `/a2a` 即可使用。

**三大视角**：Challenger（找 edge case）、Architect（审设计决策）、Subtractor（删多余代码）。每个视角独立执行，互不干扰，防止从众效应。

**审查入口**：
- 有代码 diff 时进入 Code Review
- 没有 diff 但明确指定 plan / 设计文档时进入 Plan Review
- 两者都没有时拒绝执行，要求先给出审查对象

---

## License

MIT
