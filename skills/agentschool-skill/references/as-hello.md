# as hello — Hello World 接口

调用服务端 Hello API，验证鉴权 / 联通性。分两种模式：**公开**（默认，无需登录）与**受保护**（`--auth`，需要人类会话）。

---

## 公开 Hello（默认）

```bash
as hello
```

- 调用：`GET /api/v1/public/hello`
- 鉴权：**不需要登录**
- 响应：

```json
{
  "message": "你好，陌生人！来 AgentSchool 让更多人用好 AI 吧。"
}
```

- CLI 显示：

```
你好，陌生人！来 AgentSchool 让更多人用好 AI 吧。
```

> 公开版**没有 `user` 字段**，因为服务端拿不到身份。这是验证服务端是否起来、接入地址是否正确的最快方式。

---

## 受保护 Hello（`--auth`）

```bash
as hello --auth
```

- 调用：`GET /api/v1/auth/me`（认证端点；CLI 持人类会话时调用）
- 鉴权：**需要人类登录会话**（邮箱验证码登录后的会话凭据）
- 响应：

```json
{
  "email": "oneopcai@agent.qq.com",
  "full_name": "一人AI突围"
}
```

- CLI 会显示：

```
你好，<姓名或邮箱>！欢迎来到一人AI突围。
用户：<邮箱>
ID:   <用户ID>
```

Agent 的身份与学生证验证不用本命令——用 `as +me`（持 ApiKey 直调 `/auth/me`，输出学生证元数据/租户/掩码）。业务请求固定使用 `X-Api-Key`，`Authorization: Bearer` 槽位只属于会话 access token，不要把 ApiKey 填入 Bearer。

---

## 参数

| 参数 | 类型 | 必填 | 默认 | 说明 |
|------|------|:----:|------|------|
| `--auth` | bool | — | `false` | 调受保护版（需要人类会话） |

---

## 典型用途

1. **验证服务端是否起来**（不需要登录）：

   ```bash
   as hello
   ```

2. **验证"人类会话是否有效"**：

   ```bash
   as hello --auth
   # 成功：显示个性化欢迎语
   # 失败：需要 `as auth login`
   ```

3. **验证 Agent 学生证接入**：用 `as +me`（不是 hello）。

---

## 响应处理规则

- **原样展示** `message` 字段，不得翻译或改写用户姓名。
- `user`/`email` 字段为字符串，**原样展示**，不得编造为"用户 xxx"。
- 不要把整个 JSON 直接吐给用户——CLI 已经把 `message` 加粗高亮、`user` 小字灰色展示。

---

## 常见错误

| 错误现象 | 原因 | 解决方案 |
|---------|------|---------|
| `--auth 需要先登录` | 受保护模式无人类会话 | 先 `as auth login`（Agent 接入用 `as +connect`，不需要 hello） |
| `Connection refused` / 网络错误 | 服务端不可达 / 自部署 AS_API_BASE 设置错误 | 检查网络；自部署用户确认环境变量 |
| `OAuth 凭证无效或已过期` | 人类会话过期 | 重新 `as auth login` |

## 参考

- [as](../SKILL.md) — 全部命令概览
- [as-auth](./as-auth.md) — 登录 / 登出 / 状态
- [as +me](./as-me.md) — Agent 身份与学生证验证
