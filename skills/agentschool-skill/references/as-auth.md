# as auth — 人类账号会话

当前 CLI 的 `as auth` 是邮箱验证码登录，服务对象是用户本人和需要用户会话的管理操作。它不是 OAuth 2.0 客户端登录，也不是 Agent 业务接入的前置步骤。OAuth 2.0 / OIDC、Code + PKCE 和管理 CLI 客户端属于架构文档中的待开发目标，当前版本没有上线 Device Flow 教程或 PKCE 流程。

## login

```bash
as auth login
as auth login --email <你的邮箱>
as auth login --email <你的邮箱> --code <6位验证码>
```

命令发送邮箱验证码；首次验证可完成注册，成功后保存人类会话到 `~/.agentschool/credentials.json`。未传参数时按提示交互输入。邮箱和验证码必须由用户本人提供；不要让 Agent 猜测或代填。

该会话供用户侧的凭据管理等命令使用。Agent 调业务能力使用用户签发的 ApiKey，不需要先执行 `as auth login`。

## status / logout

```bash
as auth status
as auth logout
```

`status` 检查本地会话并可调用 `/auth/me` 验证；`logout` 清除本地会话文件。它们不会创建、显示或替换 Agent 的 ApiKey。登出也不等于撤销服务端的 ApiKey 或其他授权。

## 与 Agent 接入的边界

| 目的 | 当前入口 | 凭据 |
|---|---|---|
| 用户注册/登录、管理自己的凭据 | `as auth login` | 邮箱验证码会话 |
| Agent 接入并调用业务 API | `as +connect` | 用户在 Web `/keys` 签发后取得的 ApiKey |
| 查看当前身份 | `as +me` | 优先 ApiKey，必要时才用人类会话 |

历史设备授权教程已从本技能移除，不代表当前 CLI 能力。

## 常见错误

| 现象 | 处理 |
|---|---|
| 验证码过期或无效 | 重新发送验证码并在有效期内提交 |
| `401 Unauthorized` | 重新执行 `as auth login`；这只修复人类会话 |
| 网络错误 | 检查 `AS_API_BASE`/`AGENTSCHOOL_BASE_URL` 与网络，暂保留本地凭据，恢复后再验证 |

参考：[as +me](as-me.md)、[as +connect](as-connect.md)、[as onboarding](as-onboarding.md)。
