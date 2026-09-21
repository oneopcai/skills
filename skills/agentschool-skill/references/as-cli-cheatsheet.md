# as CLI 速查

当前 Node CLI 包版本 `0.3.1`，技能版本 `0.9.0`。

## 凭据与身份

| 命令 | 用途 |
|---|---|
| `as +connect` | 检查 env/keychain；缺少时引导 Web `/keys` 取件并写 keychain，再验证 |
| `as +connect --check` | 纯只读检查（零写副作用）；未接入/无法确认时退出码 1 |
| `printf '<取件码>' \| as +connect` | 自动化受控交付：取件秘密经 stdin 管道，不进 argv/进程列表 |
| `as +me` | 调 `/auth/me` 查看身份与学生证元数据 |
| `as apikey list/show` | 查看非秘密本地索引和服务端验证 |
| `as apikey clear` | 清理本地凭据，不影响服务端 |
| `as apikey use <id>` | 设默认凭据（多凭据日常零参数；短前缀可用） |
| `as auth login/status/logout` | 邮箱验证码的人类会话管理 |

多凭据：`as apikey use <id>` 设默认（日常命令零参数）；临时切换 `AGENTSCHOOL_CREDENTIAL_ID`。吊销/轮换等人工操作在 Web /keys。`AGENTSCHOOL_API_KEY`（合法 `ask_` 形态）是 headless/CI 注入模式；与显式选择同时存在时明确报冲突，不静默覆盖。keychain 凭据绑定受信 origin，切换环境不自动复用。

## 认证头

业务请求（ApiKey/学生证）固定使用 `X-API-Key: ask_...`。`Authorization: Bearer` 槽位只属于会话 access token，不要把 ApiKey 填入 Bearer，也不要把 ApiKey 当 OAuth access token 申请 refresh。不要附加已退役的 `X-Device-Id`。

## 安全边界

- fetch_code 是一次性秘密，不能进入聊天、日志、shell history 或普通自动化参数。
- 完整 ApiKey 只由取件响应进入 OS keychain；命令输出只显示掩码。
- CLI 不做本地权限判定，不读取用户真实 keychain 明文。
- 401/403/网络错误时先保留凭据并报告；不要因暂时无法验证而删除。

完整 OAuth2.0 / OIDC、Code + PKCE、第三方委托与 `client_credentials` 是架构目标，当前 CLI 不提供这些教程或命令。

