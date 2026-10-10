# as CLI 速查


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
| `as auth login/status/logout` | 邮箱验证码账号会话（`--email`/`--code` 两步流；`--browser` 浏览器 PKCE） |

多凭据：`as apikey use <id>` 设默认（日常命令零参数）；临时切换 `AGENTSCHOOL_CREDENTIAL_ID`。吊销/轮换等人工操作在 Web /keys。`AGENTSCHOOL_API_KEY`（合法 `ask_` 形态）是 headless/CI 注入模式；与显式选择同时存在时明确报冲突，不静默覆盖。keychain 凭据绑定受信 origin，切换环境不自动复用。

## 公众号图文与内容编排

| 命令 | 用途 |
|---|---|
| `as wechatoa article import <md> --assets <文章根> [--cover <封面图>] [--force]` | MD+配图建文章（配图按 MD 顺序上传；`--cover` 设封面——不传则发布回退首图；同内容重复 import 复用既有文章，`--force` 强制新建） |
| `as wechatoa article prepare/preview/publish` | 压缩配图定版 revision → 本地预览 → 发布草稿箱（幂等键确定性派生，中断重跑同命令即重放） |
| `as wechatoa draft publish --file <html> [--cover <封面>] --content-images <图...>` | HTML 直发草稿；正文图与封面超微信 2MB 限制时服务端自动压缩（结果逐张提示前后大小） |
| `as sheaf` | 内容创作编排十域：captures/topics/masters/variants/assets/briefs/deliveries/receipts/skill |

配图/封面超 2MB 不再是调用方约束：服务端 image 链自动压缩（正文 wechat-content / 封面 wechat-cover 预设，预算均 1.8MB）；压缩服务不可达/压缩失败按 503/502 报错，凭据链未放行（workload grant 缺失）按 403 报错——均不静默降级。

`draft publish --content-images` 的占位符格式：正文 HTML 中 `<img data-wx-image src="本地引用">`，服务端按 `data-wx-image` 标记的文档顺序与 `--content-images` 入参顺序一一对应替换为微信图床 URL。

## 认证头

业务请求（ApiKey/学生证）固定使用 `X-Api-Key: ask_...`。`Authorization: Bearer` 槽位只属于会话 access token，不要把 ApiKey 填入 Bearer，也不要把 ApiKey 当 OAuth access token 申请 refresh。不要附加已退役的 `X-Device-Id`。

## 安全边界

- fetch_code 是一次性秘密，不能进入聊天、日志、shell history 或普通自动化参数。
- 完整 ApiKey 只由取件响应进入 OS keychain；命令输出只显示掩码。
- CLI 不做本地权限判定，不读取用户真实 keychain 明文。
- 401/403/网络错误时先保留凭据并报告；不要因暂时无法验证而删除。

账号会话由 OAuth2 授权链签发（浏览器 PKCE 或 CLI 邮箱验证码两步流，两种登录方式）；第三方委托与 `client_credentials` 仍是架构目标，当前不提供其教程。

