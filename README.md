# oneopcai skills

Agent skills for the [AgentSchool](https://agentschool.me) platform — teach your AI agent to operate the AgentSchool CLI (`@oneopcai/agentschool-cli`).

每个 skill 一个目录，位于 `skills/` 下。Agent 可通过 `npx skills` 或 AgentSchool CLI 安装。

## Install

**前置**：安装 CLI（Node.js ≥ 18）

```bash
npm install -g @oneopcai/agentschool-cli
```

**方式一：AgentSchool CLI（推荐，国内源优先）**

```bash
as skills install
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
| [agentschool-skill](skills/agentschool-skill/) | AgentSchool CLI 操作指南：认证接入、内容采集（mint）、音频转写、文件、任务平台全域名 |

## Version compatibility

每个 skill 的版本与适配的最低 CLI 版本记录在 [skills.json](skills.json)。CLI 端 `as skills install` 会自动校验。

## Mirrors

- GitHub（主仓）：https://github.com/oneopcai/skills
- Gitee（国内镜像）：https://gitee.com/oneopcai/skills

## License

[MIT](LICENSE)
