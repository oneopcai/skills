# as auth — 账号会话（邮箱验证码）

`as auth` 是邮箱验证码登录，服务对象是用户本人和以邮箱账号身份操作的 agent（管理 ApiKey、查看账号等）。默认 CLI 原生两步流（零浏览器零回调，headless/agent 友好）；`--browser` 走系统浏览器 PKCE（人机场景）。两条路产物同为 OAuth 会话 token（hydra 签发、原生 refresh），存于 `~/.agentschool/credentials.json`。

注册开放：`@agent.qq.com` 全域邮箱首次验码自动注册（自动建号+个人租户+欢迎邮件）；其它域名暂不支持。

它不是 Agent 业务接入的前置步骤——业务调用走 ApiKey（见 [as +connect](as-connect.md)）。

## login

```bash
as auth login
as auth login --email <你的邮箱>
as auth login --email <你的邮箱> --code <6位验证码>
```

两步流（推荐，agent 自动化形态）：

```bash
as auth login --email <邮箱>               # 第一步：发验证码到邮箱
# （从邮箱读到 6 位验证码；agent 可读自有邮箱自动取码）
as auth login --email <邮箱> --code <码>   # 第二步：凭码登录
```

- 第一步会记住在途发码（10 分钟有效）；第二步凭同一封码完成，不会重发
- 验证码来自该邮箱的信箱——持有邮箱者（用户本人或 mailbox 归属的 agent）提供，不要凭空猜测
- 无参调用=交互式逐步提示；`--browser`=旧系统浏览器 PKCE 流
- 需要 CLI ≥ 0.5.4

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
| 验证码过期或无效 | 重新 `--email` 发码并在有效期内提交（在途码作废） |
| "没有该邮箱的在途发码记录" | 先跑第一步 `--email` 发码，再用返回的码跑第二步 |
| `401 Unauthorized` | 重新执行 `as auth login`；这只修复人类会话 |
| 网络错误 | 检查 `AS_API_BASE`/`AGENTSCHOOL_BASE_URL` 与网络，暂保留本地凭据，恢复后再验证 |

参考：[as +me](as-me.md)、[as +connect](as-connect.md)、[as onboarding](as-onboarding.md)。
