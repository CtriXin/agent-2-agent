# DEV — 给 Claude 看的开发说明

> 每次修改完 skill 文件后，必须执行以下同步流程。

## 同步到开源 repo

```bash
cp -r ~/.claude/skills/a2a/* ~/agent-2-agent/
cd ~/agent-2-agent
git add .
git commit -m "版本号 + 改动说明"
git push origin main
```

## 版本号规则

- patch（x.x.**+1**）：bugfix、文字修正、路径修正
- minor（x.**+1**.0）：新功能、流程调整、新增文件
- major（**+1**.0.0）：架构重构、breaking change

## 改完一定要做的事

1. 更新 `CHANGELOG.md`（顶部加新版本）
2. 更新 `SKILL.md` frontmatter 里的 `version`
3. 执行上方同步命令

## 当前 repo

- 本地 skill：`~/.claude/skills/a2a/`
- 开源 repo：`~/agent-2-agent/` → `https://github.com/CtriXin/agent-2-agent`
