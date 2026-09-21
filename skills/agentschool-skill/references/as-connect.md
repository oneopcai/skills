# as +connect — 接入状态机与取件（enroll）

`as +connect` 是业务接入的唯一入口，内部完成取件（enroll）。公开命令面没有独立的取件命令；取件码（fetch_code）也没有 argv/env 入口。它是用户绑定 AI Agent 持 ApiKey 调用开放 API 的接入流程；不是 OAuth 登录、不是 `client_credentials`，也不是设备配对。

```bash
# 引导接入（交互终端）：检查 → 打开 Web /keys → 受控输入取件码 → 验证
as +connect

# 纯只读检查（CI 友好；未接入/无法确认时退出码 1）
as +connect --check

# 自动化受控交付：取件秘密经 stdin 管道进入（不进 argv/进程列表）
printf '<取件码>' | as +connect
```

## 状态机（spec 034 K-1）

| 输入条件 | 行为 |
|---|---|
| `--check` | 纯只读：不删凭据、不消费取件码、不开浏览器、不读 stdin；无法确认已接入即退出 1 |
| stdin 管道有取件码 | 明确的新接入意图：即使旧证有效也必须取件，并验证返回的精确 `credential_id` |
| 已有可用凭证 | typed 验证：valid / invalid（仅可信自省 401）/ forbidden（403，凭据保留）/ unknown（网络、5xx）；任何情况都不自动删除凭据 |
| 多把学生证 | 逐把体检只报告；日常使用 `as apikey use <id>` 设默认，`+connect` 新接入自动设默认 |
| 无凭证（交互） | 打开 Web `/keys` 引导用户签发 → 隐藏输入取件码 → 取件 → 写 keychain → 验证新证 |
| 无凭证（非交互且无管道取件码） | 直接失败：取件码是秘密，无 argv/env 入口 |

取件请求只带 `fetch_code` 和 `client_label`；`client_label` 仅用于展示和审计，不是身份验证或安全因子。CLI 不生成预配码；用户必须先在 Web `/keys` 签发取件码。

## 受控秘密输入（K06）

取件码没有也不允许 argv/env 入口（进程参数、环境变量、聊天提示词都会留痕）。两条受控路径：

1. 交互 TTY：隐藏输入，输入不回显，Ctrl+C 安全取消（取件码未被使用）。
2. stdin 管道（Agent 自动化）：`printf '<取件码>' | as +connect`，只取首行；非 `fetch_` 前缀直接拒绝且不执行任何写操作。

不要把取件码粘贴到聊天、工单、日志、shell history 或任何命令行参数，也不要要求用户把取件码发到对话里。

## 取件与保存（K05）

1. **领取前存储预检**：本地凭据存储（keychain/索引）不可用时直接拒绝领取——取件码未被消费。无 OS keychain 的 headless 环境不支持取件接入（env `AGENTSCHOOL_API_KEY` 注入是 headless 的受支持用法）。
2. 消费取件码（一次性）→ 拿到 full_key（仅此一次，明文只进 keychain 不上屏，输出只显示掩码）。
3. 两段式落库：secret 先行；仅索引失败≠明文丢失——元数据暂存后任意凭据命令自动修复索引。
4. 失败不打印任何明文/取件码。已消费码 + 存储全失败的恢复路径 = 用户到 Web `/keys` 重签取件码后重新 `as +connect`；旧码不可重放、原 key 不再交付。

## 凭据解析（K03/K08，全命令唯一解析器）

- `AGENTSCHOOL_API_KEY`（合法 `ask_` 形态）= headless/CI 注入模式；与显式选择（`--agent-name`/`AGENTSCHOOL_CREDENTIAL_ID`）同时存在时**报冲突**，要求二选一，不静默覆盖。
- keychain 凭据绑定签发时的受信 origin：切换 `AS_API_BASE` 后不自动复用另一环境的学生证，需在目标环境重新接入。
- `credential_id` 精确命中或 `client_label` 唯一命中才可用；零命中报错（不回退人类会话或另一张证）、多命中歧义。
- 学生证只发 https 目标（本机 localhost/127.x/::1 明文 http 例外）。

## 生命周期管理

```bash
as apikey list
as apikey show --credential-id <id>
as apikey clear
```

`revoke`、`rotate`、`sync` 需要人类会话（OAuth），且改服务端状态；遇到 401/403 或网络错误不要删除本地 key，先保留凭据并报告失败原因。`clear` 只清本地存储，不撤销服务端 key。

## 当前支持与目标

当前支持的是用户签发、Agent 持有、服务端在线验证的受限 ApiKey。完整 OAuth 2.0 / OIDC、原生应用 Code + PKCE、管理 CLI OAuth 客户端和第三方 `client_credentials` 是架构目标，尚未在此 CLI 上线，不应写成现行操作步骤。
