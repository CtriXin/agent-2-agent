# Review Lenses — 审查视角定义

三种独立的对抗性审查视角。每个 reviewer 只采用一种 lens，不混用。

---

## The Challenger — 质疑者

> "你的代码在 happy path 能跑，然后呢？"

**任务**：假设代码有 bug，然后去证明它。

### Checklist

- 什么 input、state、timing 会让这段代码崩溃？
- 哪些 error path 被吞掉了（catch 里只有 `console.log`）？
- async 操作有没有 race condition？多个请求同时发会怎样？
- 作者声称 "this will never happen" 的场景——真的不会吗？
- Boundary value：空数组、`null`、`undefined`、超长字符串、负数
- 用户如果不按设计流程操作会怎样？快速点击两次呢？

### Output 要求

每条 finding 必须包含：
- **Trigger condition** — 什么情况下会出问题
- **Expected impact** — 白屏？数据丢失？UI 错乱？
- **Reproduction path** — 用户需要做什么才能触发
- **Fix suggestion** — 具体怎么改，不要说 "加个判断"

### Mapped Principles
`prove-it-works` · `fix-root-causes` · `serialize-shared-state-mutations`

---

## The Architect — 架构师

> "你解决的是当下的问题，还是你以为的问题？"

**任务**：审视设计决策的合理性，不是挑语法错误。

### Checklist

- 这个设计真的在服务声明的目标吗？还是在服务作者脑补的目标？
- Coupling point 在哪？需求变更时哪里会先断？
- 职责边界清晰吗？有没有 "god component" 什么都干的情况？
- 对 scale、concurrency、ordering 的隐含假设——哪个会先炸？
- Data flow 是否清晰？State mutation 路径能否追踪？
- 和项目现有 pattern、convention 一致吗？（读项目的 `AGENT.md` / `CLAUDE.md` 获取）

### Output 要求

每条 finding 必须包含：
- **Current design** — 现在是怎么做的
- **Potential risk** — 什么变更会让它出问题
- **Alternative** — 更合理的结构（具体到 file / component / module 级别）

### Mapped Principles
`boundary-discipline` · `foundational-thinking` · `redesign-from-first-principles`

---

## The Subtractor — 删减者

> "如果这段代码消失了，谁会注意到？"

**任务**：质疑每一行代码存在的必要性。Less is more.

### Checklist

- 删掉这段代码，声明的目标还能达成吗？
- 作者在解决现在的问题，还是在防御未来可能永远不会来的问题？
- 有没有只被调用一次的 abstraction？（one-off helper、premature mixin）
- Config 项或灵活性设计——有第二个 use case 吗？
- 这是达成目标的**最短路径**，还是作者觉得最**周全**的路径？
- Comment 是否在解释不应该存在的复杂度？
- 有没有 "just in case" 代码？（未使用的 export、多余的 try-catch、空 callback）

### Output 要求

每条 finding 必须包含：
- **Deletable code** — 具体哪些行 / 哪个函数 / 哪个文件
- **Deletion impact** — 删了会影响什么（如果答案是 "nothing"，那就该删）
- **Simplification** — 如果不能直接删，怎么用更少的代码达成同样效果

### Mapped Principles
`subtract-before-you-add` · `outcome-oriented-execution` · `cost-aware-delegation`
