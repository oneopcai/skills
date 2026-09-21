# as services — 业务服务命令（tasks / mint / quill）

> v0.9.0 新增。全部经网关受保护路由（ApiKey 走 `X-API-Key`；`Authorization: Bearer` 槽位属于会话 access token → PEP → PDP），
> 鉴权与租户上下文由服务端解析；CLI 不做授权判定、不缓存 allow/deny。
> 自部署/本地栈：先 `export AGENTSCHOOL_API_BASE=http://localhost`（兼容 `AS_API_BASE`）。

## as tasks — 任务平台统一入口（跨业务）

所有业务重活（解析/转写/发布）都以任务形态落地，`tasks` 是统一观察与控制面。

| 命令 | 用途 | 备注 |
|---|---|---|
| `as tasks list` | 任务列表（跨业务） | `--status` / `--kind` 过滤 |
| `as tasks show <taskId>` | 任务详情 | 含 `progress` / `stage` / `result` |
| `as tasks wait <taskId>` | 等待终态（统一轮询） | `--timeout` 控上限；所有业务共用 |
| `as tasks cancel <taskId>` | 取消任务 | 终态任务返回 409 |
| `as tasks tree <taskId>` | 子任务树 | 父子编排可视化 |

## as audio — 音频转写平台

| 命令 | 用途 | 备注 |
|---|---|---|
| `as audio transcribe <file>` | 本地音频一行转写 | CLI 编排：Files 流式上传（purpose=audio.transcription_input）→ Audio JSON 提交；`--wait` 轮询出全文，`--timeout` 控等待上限 |
| `as audio transcribe --file-id <uuid>` | 复用已上传文件 | 跳过全部上传调用，直接提交转写 |
| `as audio clone / tts / realtime` | 路线图占位 | 未交付，非零 exit |

## as files — 文件平台

| 命令 | 用途 | 备注 |
|---|---|---|
| `as files upload <file> --purpose <p>` | 流式上传 | SHA-256 流式计算；`--retention-seconds` 可选 |
| `as files list` | 文件列表 | `--purpose/--status/--limit/--offset` 过滤分页 |
| `as files show <fileId>` | 文件详情 | 元数据 + 生命周期状态 |
| `as files download <fileId>` | 流式下载 | `--output` 指定路径；默认拒绝覆盖，`--force` 放行 |
| `as files delete <fileId>` | 删除文件 | 服务端软删除（204） |
| `as files policies` | 查 purpose 策略 | 扩展/MIME/大小上限的权威来源 |

## as mint — 抖音解析

| 命令 | 用途 | 备注 |
|---|---|---|
| `as mint parse <url>` | 一键解析抖音视频 | 查重→提交→等待→输出标题/作者/转写；内部即任务链 |
| 旧 mint 转写命令（弃用别名） | 弃用 | 已迁 `as audio transcribe`（别名 v0.5.0 移除，stderr 迁移通告） |
| `as mint sources` | 采集记录查询 | 子命令 `check` |

## as quill — 公众号创作助手

| 命令 | 用途 |
|---|---|
| `as quill accounts list` | 公众号配置列表 |
| `as quill accounts verify <accountId>` | 公众号连通性自检 |
| `as quill draft publish` | 草稿发布（参数多，先 `--help`） |
| `as quill drafts list / get / delete` | 微信侧草稿箱 |
| `as quill materials list / get / delete` | 素材库（图片/音频等已上传素材） |
| `as quill history list / get` | 发布历史 |
| `as quill covers` | 封面库（历史草稿用过的封面图） |

## 全链工作流（抖音 → 转写 → 公众号）

```bash
as mint parse https://v.douyin.com/xxxxx/   # → taskId + 标题/作者/转写
as tasks tree <taskId>                       # 看父子编排（parse→media→asr 子任务）
as audio transcribe ./interview.mp3 --wait   # 本地音频一行转写（上传+提交+等全文）
as files list --purpose audio.transcription_input  # 查已上传的转写输入文件
as quill accounts list                       # 列公众号配置（verify <accountId> 自检连通性）
as quill materials list                      # 素材就位情况
as quill draft publish --help                # 按当前参数集发布
```

## 错误语义（网关链）

| 码 | 含义 | Agent 行动 |
|---|---|---|
| `502 pdp_unhealthy`（body 带 `pdp_status`） | PDP 可达但内部故障 | 服务端问题，稍后重试 |
| `503 pdp_unreachable` | 连不上 PDP | 服务端问题，稍后重试 |
| `401 credential_invalid` | 凭据缺失/无效 | `as apikey show` 自检 |
| `403 <reason>` | PDP 拒绝（reason 说明原因） | 按 reason 处理（如 `tenant_context_invalid`=租户归属问题） |

## 进阶用法（详细版，2026-09-20 从 onboarding 文档下沉）

### mint 解析语义

- **多 URL 批量**：`as mint parse <url1> <url2> ...` ——滚动并发池（并发数由服务端集中管控，用户无需传参），逐个完成逐个出详情块，聚合报告落 `~/.agentschool/mint/_batch_*.json`
- **查重短路**：已采集过的 URL 直接跳过（不消耗 ASR 配额）；失败过的 URL 会明确显示上次失败原因并指路 `--retry`
- **常用参数**：`--skip-transcribe`（省配额跳转写）/ `--retry`（全链重跑）/ `--transcribe-only`（补转写：对跳过/失败转写的内容用已上传音频快速补齐并回写，10 秒级）/ `--no-wait`（只拿 task_id）
- 中断等待（Ctrl-C）不丢任务：`as tasks wait <task_id>` 续接
- 终态输出带 `🆔 内容ID`：`as mint get <id>` 详情 / `as mint comments <id>` 评论 / `as mint download <file_id>` 资产下载

### 任务平台（统一入口）

```bash
as tasks list --service mint --limit 5    # --service/--status/--type 过滤
as tasks show <task_id>                   # 详情（progress/stage/result）
as tasks wait <task_id>                   # 等待终态
as tasks cancel <task_id>                 # 取消
as tasks tree <task_id>                   # 子任务树（--max-depth 控层数）
```

task_type 命名 `<service>.<action>`（如 `mint.douyin_parse`）。

### quill 发布规则

- **微信草稿必须带封面**：`--cover <图>` 新上传，或 `--thumb-media-id <已有封面ID>` 复用（从 `as quill history get <id>` 的 `thumb_media_id` 字段拿）
- `--update-media-id <media_id>` 走更新模式（同 media_id 覆盖，不占新草稿位）
- 微信 `errcode=40007`（invalid media_id）= 草稿缺封面
- 连通性问题先 `as quill accounts verify <id>`（IP 白名单/密钥错误有可读提示）
