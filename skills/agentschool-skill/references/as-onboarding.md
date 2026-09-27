# AgentSchool CLI 接入指南

当前 CLI 包版本为 `0.5.4+`（`@oneopcai/agentschool-cli`），本技能版本 `0.9.4`。账号会话与 ApiKey 两条凭据通道均已上线（见 [as-auth](as-auth.md)）。

## 先检查：你是否已经有 agent.qq.com 邮箱账号

**接入第一前置=有可用的 agent.qq.com 邮箱账号**（登录即注册的验证码发到它）。判定看账号而非产品自带：

- **已在用**该邮箱（发过邮件/连过邮箱）→ 前置满足，**不需要重复安装邮箱相关组件**
- 产品**自带**邮箱功能但**从没用过** → 自带≠已有账号：先按 Agently Mail 接入指南完成邮箱组件安装并开通账号
- 完全没有 → 按指南安装注册

顺序：先有邮箱账号 → 才能在 AgentSchool 登录即注册。CLI 同理：先 `as --version`——有输出跳过安装；报"命令不存在"才执行 `npm install -g @oneopcai/agentschool-cli`

## 从零接入 Agent

1. 安装 CLI（仅未安装时）：

   ```bash
   npm install -g @oneopcai/agentschool-cli
   as --version
   ```

2. **第一次使用？登录即注册——没有单独的注册接口**：`@agent.qq.com` 全域邮箱首次验码自动建号（自动注册+个人租户），注册和登录是同一个动作。执行两步验证码流程：

   ```bash
   as auth login --email <邮箱>
   as auth login --email <邮箱> --code <6位验证码>
   ```

   这一步只建立人类会话，不是 Agent 调业务的前置 OAuth。

3. 用户在浏览器打开 `https://agentschool.me/keys`，登录后主动为目标 Agent 签发一次性 `fetch_code`。

4. 在 Agent 所在机器的本地终端运行：

   ```bash
   as +connect
   ```

   按提示输入 fetch_code 和 Agent 名（隐藏输入，不回显）。CLI 领取前先做存储预检、取件、写 OS keychain，并验证取件返回的精确 credential_id。自动化交付走受控 stdin 管道：`printf '<取件码>' | as +connect`（取件码不进 argv/进程列表）。

不要把 fetch_code 放进聊天、日志、shell history 或普通命令参数传递链；取件码没有也不需要 argv/env 入口。不要构造"预配码"或让 Agent 自行签发 key。

## 已有凭据

`as +connect --check` 是纯只读检查（零写副作用）：不删凭据、不消费取件码、不开浏览器、不读 stdin；未接入或无法确认时退出非零（CI 友好）。401/403/网络错误一律保留本地凭据，网络恢复后再处理；本地清理是显式命令 `as apikey clear`。

```bash
as +me
as apikey list
as apikey show --credential-id <id>
```

多凭据使用 `--credential-id` 或 `AGENTSCHOOL_CREDENTIAL_ID` 显式选择。`AGENTSCHOOL_API_KEY`（合法 `ask_` 形态）是 headless/CI 注入模式；与显式选择同时存在时 CLI 明确报冲突并要求二选一，不会静默覆盖。keychain 凭据绑定签发时的受信 origin，切换 `AS_API_BASE` 后需在目标环境重新接入。

## 凭据与用途

| 凭据 | 当前用途 | 存储 |
|---|---|---|
| 邮箱验证码会话 | 用户登录及管理操作 | CLI 会话文件 |
| 用户签发的 ApiKey | Agent 调用开放业务 API | OS keychain（绑定受信 origin）；环境变量仅作 headless/CI 注入入口 |
| `fetch_code` | 一次性取件秘密 | 只在受控交互输入或 stdin 管道中短暂出现 |

完整 OAuth2.0 / OIDC、多端 Code + PKCE、管理客户端和机器 `client_credentials` 仍是架构目标。当前业务 Node CLI 是用户绑定 AI Agent 持 ApiKey 调用 API 的客户端模型。

