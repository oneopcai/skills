---
name: agentschool-skill
version: 0.9.2
description: "让你的 AI 直接和 AgentSchool 对话 —— 一行命令搞定鉴权、查额度、调能力、写技术方案报告。当用户想把 AgentSchool 接入 Agent 流程、做 Demo、或为 Agent 找可商用的技术能力时使用本技能。"
metadata:
  requires:
    bins: ["as", "agentschool"]
    node: ">=18"
  cliHelp: "as --help"
  projectHome: "https://agentschool.me"
  scopeList:
    - enrollment: 入学（用户签发 fetch_code → Agent 取件 ApiKey）
    - auth: 人类邮箱验证码会话
    - capability: 能力探测（搜索/详情/导出）
    - apikey: 凭据管理（list/show/use/clear 本地；吊销/轮换等人工操作在 Web /keys）
    - services: 业务服务调用（经网关，鉴权判定全在服务端 PDP）
    - security: 安全规则（keychain 保存、秘密不进聊天与日志）
---

# AgentSchool CLI skill

当前 Node CLI 包版本为 `0.4.x`，随包技能版本为 `0.9.1`。本技能帮助 Agent 使用已安装的 `as` 命令查询能力并调用业务 API。

## 认证模型

业务 Node CLI 的当前模型是：用户在 Web `/keys` 主动签发取件码，用户绑定的 AI Agent 用取件码换取受限 ApiKey，随后持 key 调用开放 API。它不需要 `as auth login`，也不是 OAuth `client_credentials`。

`as auth login` 当前只是邮箱验证码的人类账号会话，供用户侧管理操作使用。架构中的 OAuth 2.0 / OIDC、Code + PKCE、第三方委托和管理 CLI OAuth 客户端是待开发目标，不能当成当前命令教程。历史设备授权和配对教程均不适用。

## 接入与验证

```bash
as +connect
as +connect --check
as +me
as apikey list
as apikey show
as apikey use <credential_id>
```

`as +connect` 是统一接入状态机（spec 034 K-1）：

1. `--check`：纯只读检查——零写副作用（不删凭据、不消费取件码、不开浏览器、不读 stdin）；未接入或无法确认时退出码 1（CI 友好）。
2. 管道 stdin 里出现取件码 = 明确的新接入意图：即使已有有效旧证也必须执行新接入，并验证取件返回的精确 `credential_id`（不按 label/env 重选、不误报旧证成功）。
3. 无新接入意图时检查已有凭证：验证结果 typed（valid / invalid=仅可信自省 401 / forbidden=403 / unknown=网络、5xx）。**任何情况都不自动删除本地凭据**；本地清理是独立显式命令（`as apikey clear`）。
4. 无可用 key 时进入引导：打开 Web `/keys` → 用户签发取件码 → 受控输入 → 取件 → 写 keychain → 验证新证。

CLI 不生成预配码；`client_label` 只是展示和审计字段。

fetch_code 和完整 ApiKey 都是秘密，**没有 argv/env 入口**（进程参数与环境会留痕）。只有两条受控交付路径：交互终端的隐藏输入（输入不回显），或 stdin 管道 `printf '<取件码>' | as +connect`（Agent 自动化场景）。不要把 fetch_code 粘贴到聊天、日志、shell history 或任何命令行参数。CLI 运行时必须从 keychain 读取 key，Agent 不得通过 cat、导出或日志提取明文。

凭据解析（全命令唯一解析器）：`AGENTSCHOOL_API_KEY` 环境变量是 headless/CI 注入模式；存在合法 ask_ 形态的 env key 且同时给出显式选择（`AGENTSCHOOL_CREDENTIAL_ID`）时**明确报冲突**，要求二选一，不静默覆盖。keychain 凭据按签发时绑定的受信 origin 过滤——切换 `AS_API_BASE` 不自动复用另一环境的学生证。多凭据用 `as apikey use <credential_id>` 设默认（日常命令零参数；`+connect` 新接入自动设默认），临时切换用 `AGENTSCHOOL_CREDENTIAL_ID`；歧义时 CLI 列出候选并要求先 use。401/403/网络错误一律保留本地凭据，待可达后再验证或修复。

## 命令概览

| 命令 | 用途 |
|---|---|
| `as auth login/status/logout` | 邮箱验证码的人类会话 |
| `as +connect` / `as +me` | Agent 接入、身份验证 |
| `as apikey list/show/use/clear` | 本地凭据索引、验证、设默认、清理（吊销/轮换=Web /keys） |
| `as capability search/show/providers/export` | 查询、查看、导出能力卡 |
| `as mint parse` | 抖音解析流水线 |
| `as audio transcribe` | 音频上传、转写与等待 |
| `as files upload/list/show/download/delete/policies` | 文件平台 |
| `as tasks list/show/wait/cancel/tree` | 跨业务任务平台 |
| `as quill accounts/drafts/history/materials/covers` | 公众号工作台 |
| `as skill list/install/update` | 技能分发 |
| `as doctor` | 环境、网络和凭据自检 |

公开命令以 `as --help` 实际注册为准：取件没有独立命令（是 `as +connect` 的内部流程），注册/登录也只有 `as auth login` 一个入口；身份命令唯一写法是 `as +me`。取件的自动化交付用 stdin 管道：`printf '<取件码>' | as +connect`。

业务服务的详细参数、错误语义和能力域说明见 [as-services.md](references/as-services.md)、[capability-domains.md](references/capability-domains.md)、[providers-snapshot.md](references/providers-snapshot.md)。能力卡格式见 [agent-card-schema.md](references/agent-card-schema.md)。

## 业务调用

业务请求固定使用 `X-Api-Key: ask_...`。网关的 `Authorization: Bearer` 仅用于 JWT 会话，不把 ApiKey 填入 Bearer。CLI/Agent 不做本地权限判定，allow/deny 由服务端 PDP 决定。遇到 401/403 按服务端响应处理，不自动换 key 或删除 keychain 条目。

常用示例：

```bash
as capability search image --limit 5
as capability show <id>
as mint parse https://v.douyin.com/xxxxx
as audio transcribe audio.mp3 --wait
as files upload video.mp4 --purpose mint.source_video
as tasks list --service mint --limit 10
as quill drafts list
```

## 安全规则

- 用户必须亲自在 Web `/keys` 签发 Agent 的 fetch_code；Agent 不自行签发 ApiKey。
- 不把 fetch_code、ApiKey、邮箱验证码或人类会话 token 发到聊天、日志、代码仓库或命令历史；取件秘密只走受控 stdin（交互隐藏输入或管道），没有也不要求 argv/env 入口。
- ApiKey 仅由取件响应进入 OS keychain；输出只显示掩码。
- `as apikey clear` 只清本地；服务端吊销/轮换需要人类会话且不可因网络失败而假定成功。
- 认证头和权限以当前服务合同为准，目标架构的 OAuth2.0 方案上线前不提前引用。

## 参考

- [as-auth.md](references/as-auth.md)
- [as-onboarding.md](references/as-onboarding.md)
- [as-connect.md](references/as-connect.md)
- [as-me.md](references/as-me.md)
- [as-cli-cheatsheet.md](references/as-cli-cheatsheet.md)
- [as-services.md](references/as-services.md)
