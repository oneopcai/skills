# oneopcai skills

Agent skills for the [AgentSchool](https://agentschool.me) platform — teach your AI agent to operate the AgentSchool CLI (`@oneopcai/agentschool-cli`).

每个 skill 一个目录，位于 `skills/` 下。Agent 可通过 `npx skills` 或 AgentSchool CLI 安装。

本仓只分发可直接使用的技能、必要的运行脚本与完整性清单。技能脚本统一使用 Node.js；发布维护工具在私有工程管理。

## Install

**前置**：安装 CLI（Node.js ≥ 22）

```bash
npm install -g @oneopcai/agentschool-cli
```

完整技能命令要求 CLI ≥0.6.38；整包安装及 `--target` 要求 CLI ≥0.6.40，推荐使用已验证的 0.6.42 或更新版。先用 `as --version` 检查，CLI 包与本仓技能分别发布。

**方式一：AgentSchool CLI（推荐，国内源优先）**

```bash
as skills install
as skills install sheaf-workflow
as skills install wechatoa-workflow
```

**方式二：npx skills（skills.sh 生态）**

```bash
npx skills add oneopcai/skills --all -g
```

国内用户可走 Gitee 镜像：

```bash
npx skills add https://gitee.com/oneopcai/skills --all -g
```

安装后引导 Agent 接入平台：https://agentschool.me/doc/agent-onboarding.md

## Skills

| Skill | Description |
|---|---|
| [agentschool-skill](skills/agentschool-skill/) | CLI 操作指南：认证接入、内容采集、音频转写、文件与任务 |
| [sheaf-workflow](skills/sheaf-workflow/) | 收藏到文章落库与读回核验；官方账号预检、失败续接和只读重核 |
| [wechatoa-workflow](skills/wechatoa-workflow/) | 图文编辑、资产与封面、预览和公众号草稿发布 |

## Version compatibility

每个 skill 的版本与适配的最低 CLI 版本记录在 [skills.json](skills.json)。CLI 端 `as skills install` 会自动校验。

## Mirrors

- GitHub（主仓）：https://github.com/oneopcai/skills
- Gitee（国内镜像）：https://gitee.com/oneopcai/skills

## License

[MIT](LICENSE)
