# as +me — 查看身份

`as +me`（唯一写法，没有 `me` 短别名）调用服务端 `/api/v1/auth/me` 并展示当前用户、学生证元数据、租户和层级。它是查询命令，不会签发 key。

```bash
as +me
as +me
as +me --agent-name <client-label>
```

凭据解析走全命令统一解析器：`AGENTSCHOOL_API_KEY` 环境变量（合法 `ask_` 形态，headless 注入）优先；但与显式选择（`AGENTSCHOOL_CREDENTIAL_ID`）同时存在时明确报冲突，要求二选一，不静默覆盖。keychain 凭据按签发时绑定的受信 origin 过滤，切换环境不自动复用。多凭据时 CLI 列出候选并要求先 `as apikey use <credential_id>` 设默认（`+connect` 新接入自动设默认）；临时切换用 `AGENTSCHOOL_CREDENTIAL_ID`。完整 ApiKey 永不显示，输出使用掩码。CLI 不读取或输出用户真实 keychain 明文。

ApiKey 路径代表 Agent 绑定的学生证；人类会话路径只代表用户登录身份，不能替代 Agent 的业务 ApiKey。没有学生证时运行 `as +connect`，不需要先 `as auth login`。

## 错误处理

- `401`：凭据无效或会话过期。ApiKey 先保留并检查服务端状态；人类会话才重新 `as auth login`。
- `403`：权限或状态被服务端拒绝。保留本地凭据，按服务端原因处理，不自动删除。
- 网络错误：保留凭据，恢复网络后重试。

