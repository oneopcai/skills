---
name: sheaf-workflow
version: 1.0.0
description: "内容创作全旅程 skill —— 从收藏素材到公众号草稿落箱一条链：收藏→选题→项目→母稿确认→账号稿变体→封面/正文图资产集合→投递意图 prepare→经 wechatoa 建稿→reconcile 回执核对。当用户要『把这篇素材做成公众号文章并放进草稿箱』『走一遍 sheaf 创作流程』『从链接到草稿』时使用本技能。"
metadata:
  requires:
    bins: ["as"]
    node: ">=22"
  cliHelp: "as sheaf --help"
  projectHome: "https://agentschool.me"
  scopeList:
    - captures: 收藏入库（链接/分享文本；幂等键重试安全）
    - sources: 来源与解析（from-mint 复用已解析内容；parse 按需解析）
    - topics: 选题与评估（证据来源 + 规则版本显式保存）
    - projects: 内容项目（选题→母稿→变体的组织单元）
    - master: 母稿（CAS 草稿编辑 + 不可变确认版本）
    - variants: 账号稿变体（target=wechatoa,账号ID；版本固定来源）
    - assets: 图片资产集合（不可变 revision 链；cover/content 槽位）
    - deliveries: 投递意图与回执核对（prepare 固定 payload → wechatoa 建稿 → reconcile）
    - skills: Skill 执行登记（本 skill 运行时自登记，聊天历史不当事实源）
---

# Sheaf 内容创作工作流（收藏 → 公众号草稿箱）

`as sheaf` 命令组来自 npm 包 `@oneopcai/agentschool-cli`（≥0.6.20）。本技能把
sheaf（内容编排）与 wechatoa（公众号平台）组合成一条完整旅程：**素材进 →
草稿箱出**，每一步幂等可重试、中断可续。

## 核心概念（先读）

- **不可变链**：母稿确认版本、变体版本、画像版本、资产集合 revision 都是
  追加式不可变——改内容=新建版本，不覆盖历史。
- **CAS 并发令牌**：母稿编辑/确认必须带 `--if-match <draftVersion>`（首次
  创建用 `0`；响应里拿新值）。不匹配返回 409，重新 `as sheaf master get` 取。
- **幂等键**：写操作带 `--client-request-id`（或 `--idempotency-key`）——网络
  重试同键返回原结果；不传则每次生成新键（不可跨次重试）。
- **投递三段式**：`deliveries prepare`（sheaf 固定 payload+资产+账号）→
  `as wechatoa draft publish`（真正建稿，带 `--intent-id` + `--idempotency-key`）
  → `deliveries reconcile`（提交回执，**服务端核对后才 synced**；unknown=安全
  降级，勿盲目重新建稿）。
- **账号边界**：平台账号（公众号）增删改在 wechatoa 工作台；sheaf 只读画像。

## 前置条件

```bash
as me                       # 已登录（未登录先 as +connect 或 as auth login）
as wechatoa accounts list   # 拿目标公众号 account-id（UUID）
```

## 完整旅程（八步）

以下命令可逐步执行（Agent 模式加 `--json` 拿稳定 camelCase 输出）：

```bash
# 1. 收藏素材（幂等键=业务唯一；重复收藏返回原结果 duplicate）
as sheaf captures add --url "https://example.com/article" --client-request-id my-topic-001
# → capture.sourceId（或稍后 as sheaf sources list 查）

# 2. 选题（绑证据来源）+ 评估（绑规则版本）
as sheaf topics create --title "AI 原生学习法（一）" --source-ids <sourceId> --json
as sheaf topics assess <topicId> --rule-version v1 --score 85

# 3. 项目（服务端把选题转 selected）
as sheaf projects create --topic-id <topicId> --title "AI 原生学习法（一）" --json

# 4. 母稿：编辑（CAS 首次 0）→ 确认（固化不可变版本）
as sheaf master edit --project-id <projectId> --title "..." --content-md "# 正文…" --if-match 0 --json
# → draftVersion=N；确认用同一值
as sheaf master confirm --project-id <projectId> --if-match N --json
# → masterVersionId

# 5. 变体（目标=serviceCode,账号ID；画像缺省用当前版本）
as sheaf variants create --project-id <projectId> --master-version-id <masterVersionId> \
  --target wechatoa,<accountId> --target-platform wechat_oa --content-kind article --json
# → variantId + accountProfileVersionId
as sheaf variants version --variant-id <variantId> \
  --content-md "# 账号稿正文（按画像改写）…" \
  --master-version-id <masterVersionId> --profile-version-id <accountProfileVersionId> \
  --content-kind article --title "..." --json
# → variantVersionId（confirmed，可投递）

# 6. 资产集合：上传图片到 Files → set 建 revision 1 → reorder 挂图
#    （用户态上传走 general.image——sheaf.* purpose 仅 sheaf 服务可用；
#     绑定白名单允许 general.image/mint.image 复用，v2 §2.7）
as files upload cover.jpg --purpose general.image --json   # → file_id
as files upload body.png --purpose general.image --json    # → file_id
as sheaf assets set --variant-id <variantId> --variant-version-id <variantVersionId> --json
as sheaf assets reorder --variant-id <variantId> --asset-set-id <assetSetId> --base-revision 1 \
  --item cover,file=<coverFileId>,purpose=general.image --item content,file=<contentFileId>,purpose=general.image --json

# 7. 投递意图（输出完整可重建材料：intentId / idempotencyKey / renderedContent / assetSetRevision）
as sheaf deliveries prepare --variant-version-id <variantVersionId> --operation-kind draft_create --json
# renderedContent.contentRef=变体版本（结构化引用）：正文经版本链取回
as sheaf variants list --variant-id <contentRef> --json   # → items[].contentMd（Agent 按画像渲染成 HTML）
# payloadAssets 里的图片 fileId 随时可取回（Files，按当前用户授权）：
as files download <coverFileId> --output cover.img

# 8. 建稿（复用 wechatoa 平台命令——sheaf 不新建微信命令）→ 回执核对
#    （兼容说明：图文文章的 MD 全生命周期另走 as wechatoa article 五命令组，
#     见 skills/wechatoa-workflow——变体投递仍走本步 draft publish，两链不混用）
as wechatoa draft publish --account-id <delivery.accountId> \
  --file article.html --title "<title>" --cover cover.img \
  [--content-images content-1.img ...] \
  --intent-id <delivery.id> --idempotency-key <delivery.idempotencyKey>
# → 输出 operation_id
as sheaf deliveries reconcile --delivery-id <delivery.id> --operation-id <operation_id>
# → synced（East-West 回执核对）；unknown=回执未到，稍后重跑 reconcile
```

## 中断续接（旅程任一步失败后）

每步产物都是 UUID，重跑对应命令即可续接（幂等键保护重复提交）：

- 母稿 409 → `as sheaf master get --project-id ...` 拿最新 draftVersion 重编辑；
- prepare 后中断 → `as sheaf deliveries list --variant-version-id ...` 找回意图
  （payload/幂等键都在），重下材料继续；
- 建稿后未核对 → 重跑 reconcile（可省略 --operation-id，按已记录操作重新核对）；
- 变体版本要改 → 新建版本（旧版不可变），再对新版本 prepare。

## Skill 执行登记（可选但推荐）

Agent 宿主执行本工作流时登记到 sheaf（聊天历史不当事实源）：

```bash
as sheaf skills run --skill-id sheaf-workflow --manifest-version 1.0.0 \
  --host <宿主名> --external-run-id <宿主run ID> --input-ref project:<projectId> --json
# 每步完成后：
as sheaf skills report --run-id <runId> --step-id <stepId> --attempt-index 1 \
  --status-claim succeeded --outputs-ref <产物引用>
```

## 一键脚本

`scripts/full-journey.sh` 把上述八步串成可独立执行的脚本（不依赖宿主）：

```bash
./scripts/full-journey.sh --account <wechatoa账号UUID> \
  [--url <素材链接>] [--title "标题"] [--cover cover.jpg] [--content-image body.png]
```

脚本同样幂等：每次运行创建新选题/项目（标题带时间戳）；重复运行不互相干扰。

## 常见错误对照

| 症状 | 原因 | 处理 |
|---|---|---|
| master edit 409 | If-Match 与当前 draftVersion 不匹配 | `as sheaf master get` 取新值重编辑 |
| variants create 422 | 母稿版本不是 confirmed / 账号未连接平台 | 先 master confirm；wechatoa accounts verify |
| assets reorder 409 | baseRevision 落后（已有新 revision） | `as sheaf assets set` 响应或重跑取最新 revision |
| reconcile → unknown | East-West 回执未到/超时 | 安全降级：稍后重跑 reconcile；勿盲目再次建稿 |
| prepare 200（非 201） | 同业务唯一键返回原意图 | 正常幂等语义，用返回的意图继续 |
