# agent-2-agent (a2a)

> Cross-model adversarial code review for Claude Code.
> 跨模型对抗式 code review — 谁写的代码，就让对手来审。

**Self-review is self-deception.** Claude-written code gets reviewed by Codex; Codex-written code gets reviewed by Claude. Different models have different blind spots — let them fight.

---

<img width="2720" height="1920" alt="a2a" src="https://github.com/user-attachments/assets/05e75bc8-22aa-4afe-a928-b32d719479e4" />


## Quick Start

```bash
# 1. Clone and install
git clone git@github.com:CtriXin/agent-2-agent.git
cp -r agent-2-agent ~/.claude/skills/a2a

# 2. Check environment once (cached for 15 minutes by default)
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

Refresh local status after login changes:
```bash
~/.claude/skills/a2a/scripts/preflight.sh --refresh
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
├── CLAUDE.md                   # AI agent quick-context (read this first if you're an AI)
├── README.md                   # This file
├── references/
│   └── review-lenses.md        # Challenger / Architect / Subtractor definitions
└── scripts/
    ├── preflight.sh            # Environment check + token bridge cache (with TTL)
    ├── a2a-health.sh           # One-click health check + auto-fix token bridge
    └── spinner.sh              # Animated progress indicator (terminal users)
```

## Preflight Exit Codes

```
0  READY    — Claude + Codex both available, adversarial mode ready
2  PARTIAL  — Only one CLI, single-model-multi-lens mode
3  MISSING  — No CLI available, blocked
64 USAGE    — Bad arguments
```

## Preflight Cache

- Default TTL: 900 seconds
- Cache path: `${XDG_CACHE_HOME:-~/.cache}/a2a/preflight.json`
- `--refresh`: bypass cache once and rewrite it
- `--ttl-seconds 0`: disable cache for the current run
- Preflight checks local CLI availability + auth state. It does not send a review request.

---

## Using a2a with AI Agents

This section explains how a2a works **from the agent's perspective** — useful if you're integrating a2a into your own workflow or wondering what happens under the hood.

### What is a "skill"?

A Claude Code skill is a markdown file (`SKILL.md`) that Claude loads as instructions when you invoke it with `/a2a`. It's not a binary, not a plugin — just a prompt that teaches Claude a specific workflow. The `scripts/` directory contains helper scripts that the skill calls via Bash.

### Installation for Agents

a2a needs to live in Claude Code's skill directory. Two methods:

**Method A: Symlink (recommended for development)**
```bash
git clone git@github.com:CtriXin/agent-2-agent.git ~/agent-2-agent
ln -s ~/agent-2-agent ~/.claude/skills/a2a
```

**Method B: Copy (simpler, but manual updates)**
```bash
git clone git@github.com:CtriXin/agent-2-agent.git
cp -r agent-2-agent ~/.claude/skills/a2a
```

After installation, restart Claude Code (or start a new conversation). Type `/a2a` and Claude will recognize the skill.

### How the Cross-Model Dispatch Works

When you run `/a2a`, Claude acts as the **orchestrator**. Here's the actual execution flow:

```
You (in Claude Code): /a2a src/api/handler.ts
          │
          ▼
   Claude reads SKILL.md, runs preflight.sh --json
          │
          ▼
   git diff --stat               ← determines what changed and how much
          │
          ▼
   Scale assessment:
     < 50 lines  → Light  → 1 reviewer (Challenger only)
     50-200 lines → Medium → 2 reviewers (Challenger + Architect)
     200+ lines  → Heavy  → 2-3 reviewers
          │
          ▼
   Detect code author (git metadata / user declaration / default: Claude)
          │
          ├── Claude wrote it → dispatch to Codex:
          │     codex exec --cd "$(pwd)" --full-auto -- "review..."
          │
          └── Codex wrote it → Claude reviews:
                From Claude Code: Agent tool sub-agents (in-process)
                From Codex:       ANTHROPIC_API_KEY=$token claude -p (token bridge)
          │
          ▼
   Each reviewer runs independently (can't see others' output)
          │
          ▼
   Claude aggregates all findings + runs red-line scan
          │
          ▼
   Outputs verdict: PASS / CONTESTED / REJECT
```

**Key point**: the reviewer always runs on the **opposing model**. Claude-authored code goes to Codex via `codex exec`; Codex-authored code is reviewed by Claude (via Agent tool when orchestrated from Claude Code, or via `claude -p` + token bridge when orchestrated from Codex).

### What If Only One CLI Is Available?

If you only have Claude Code installed (no Codex), a2a falls back to **single-model-multi-lens** mode:

- Instead of dispatching to Codex, Claude spawns independent sub-agents via the Agent tool
- Each sub-agent gets one review lens (Challenger / Architect / Subtractor)
- Sub-agents run in isolation — they can't see each other's findings
- The report will say `Mode: single-model-multi-lens`

This is still useful (multiple independent perspectives > self-review), but the quality is lower than true cross-model review because the same model shares the same blind spots.

### Preflight: What It Actually Checks

Preflight checks CLI **availability** and **auth status** to determine the review mode.

```bash
# What preflight does internally:
claude --version      # → "2.1.74"  → available = true
codex --version       # → "0.114.0" → available = true
codex login status    # → authenticated = true/false/unknown
```

**Key design**: a2a is always orchestrated by Claude Code. Claude-side reviews run via **Agent tool** (in-process, inherits auth automatically). Codex-side reviews run via **`codex exec`** (Codex has its own API key).

This means:
- **Claude ready = available + (auth ok OR token bridge file exists)** — even if `claude auth status` reports false (Codex sandbox can't read Keychain), the cached token file counts
- **Codex auth matters** — `codex exec` is an external call, Codex needs its own login
- **Token bridge** — preflight extracts OAuth token from macOS Keychain → caches to `~/.cache/a2a/.claude-token` (mode 600) → Codex reads file and passes as `ANTHROPIC_API_KEY` env var to `claude -p`

**Cross-model is determined by both CLIs being ready**:
- Claude ready + Codex ready → `adversarial` mode (exit code 0)
- Only one ready → `single-model-multi-lens` mode (exit code 2)

### Common Issues

**Q: Preflight says PARTIAL but I have both CLIs installed**
Run `preflight.sh --refresh` to bypass the 15-minute cache. If it still shows PARTIAL, check that both `claude --version` and `codex --version` return valid output in your terminal.

**Q: Can I use a2a from Codex instead of Claude?**
Yes! Thanks to token bridge, Codex can call `claude -p` for cross-model review. The only prerequisite: run `preflight.sh` once from a non-sandboxed environment (normal terminal or Claude Code) to cache the OAuth token. After that, Codex reads the cached token file and passes it as `ANTHROPIC_API_KEY`. If anything goes wrong, run `a2a-health.sh` for diagnosis + auto-fix.

**Q: Review is slow / timing out**
Each reviewer has a 5-minute default timeout. For large diffs (200+ lines), the Heavy+ scale dispatches 3 reviewers in parallel, which takes ~2 minutes. If it's consistently slow, check your network connection to the model APIs.

**Q: Can I review a plan instead of code?**
Yes. If there's no git diff, explicitly point a2a at a design doc: `/a2a docs/design.md`. a2a will switch to Plan Review mode.

**Q: How do I integrate a2a into CI?**
a2a is designed for interactive use in Claude Code, not CI pipelines. For CI, consider extracting the review lenses from `references/review-lenses.md` and building your own automation.

---

## 中文说明

**agent-2-agent (a2a)** 是一个 Claude Code skill，实现跨模型对抗式 code review。

**核心原则**：Claude 写的代码让 Codex 审，Codex 写的让 Claude 审。不同模型有不同盲区——让它们互相找茬，bug 无处藏身。

**安装**：clone 本 repo，复制到 `~/.claude/skills/a2a`（或 symlink），重启 Claude Code，输入 `/a2a` 即可使用。

**双向跨模型**：
- Claude → Codex：`codex exec`（Codex 有自己的 API key）
- Codex → Claude：`claude -p` + token bridge（自动从 macOS Keychain 提取 OAuth token 缓存到文件，Codex sandbox 通过环境变量读取）
- 从 Claude Code 内发起时，Claude 侧 review 也可走 Agent tool sub-agent（in-process，天然有 auth）

**Token Bridge**：首次 `/a2a` 或 `preflight.sh` 时自动提取，用户零操作。出问题跑 `a2a-health.sh` 一键自检+修复。

**三大视角**：Challenger（找 edge case）、Architect（审设计决策）、Subtractor（删多余代码）。每个视角独立执行，互不干扰，防止从众效应。

**审查入口**：
- 有代码 diff 时进入 Code Review
- 没有 diff 但明确指定 plan / 设计文档时进入 Plan Review
- 两者都没有时拒绝执行，要求先给出审查对象

---

## License

MIT
