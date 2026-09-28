# oneopcai skills

Agent skills for the [AgentSchool](https://agentschool.me) platform — teach your AI agent to operate the AgentSchool CLI (`@oneopcai/agentschool-cli`).

每个 skill 一个目录，位于 `skills/` 下。Agent 可通过 `npx skills` 或 AgentSchool CLI 安装。

## 发布流程（维护者）

改动 skill 内容后**不要手动 git commit**，统一走一键发布（自动重算完整性清单并双推）：

```bash
bash scripts/publish.sh "publish: agentschool-skill <说明>"
```

三层防线保证 skills.json 的 sha256 清单与文件永远一致（CLI 0.5.8+ 安装时按此校验）：
1. **pre-push 本地钩子**（新 clone 跑一次 `bash scripts/install-hooks.sh`）——不一致直接拦 push
2. **GitHub Actions**（`.github/workflows/verify-hashes.yml`）——push/PR 远端校验，状态可见
3. **publish.sh 内置校验**——双推前最后跑一遍 verify


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
