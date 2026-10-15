---
name: sheaf-workflow
version: 1.0.10
description: "内容创作全旅程 skill —— 从收藏素材到公众号文章落库一条链：收藏→选题→项目→母稿确认→账号稿变体→封面/正文图资产集合→投递意图 prepare→终稿 MD+图集交 wechatoa 文章域（article import）→reconcile 平台读回核验（synced=核验时点事实一致）。当用户要『把这篇素材做成公众号文章』『走一遍 sheaf 创作流程』『从链接到文章』时使用本技能。"
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
    - deliveries: 投递意图与文章回执核对（prepare 冻结材料 → wechatoa article import 交稿 → reconcile article_receipt）
    - skills: Skill 执行登记（本 skill 运行时自登记，聊天历史不当事实源）
---

# Sheaf 内容创作工作流（收藏 → 公众号文章落库 + 读回核验）

`as sheaf` 命令组来自 CLI `@oneopcai/agentschool-cli`（≥0.6.38；可使用经核验的本地包）。本技能把
sheaf（内容编排）与 wechatoa（公众号平台）组合成一条完整旅程：**素材进 →
文章落库+读回核验 synced**，每一步幂等可重试、中断可续。
发布到微信公众号草稿箱是 wechatoa 侧的独立动作：先 `as wechatoa article prepare
<articleId>` 生成 revision，再 `as wechatoa article publish <revisionId>`，不在本旅程终点。

## 核心概念（先读）

- **不可变链**：母稿确认版本、变体版本、画像版本、资产集合 revision 都是
  追加式不可变——改内容=新建版本，不覆盖历史。
- **CAS 并发令牌**：母稿编辑/确认必须带 `--if-match <draftVersion>`（首次
  创建用 `0`；响应里拿新值）。不匹配返回 409，重新 `as sheaf master get` 取。
- **幂等键**：写操作带 `--client-request-id`（或 `--idempotency-key`）——网络
  重试同键返回原结果；不传则每次生成新键（不可跨次重试）。
- **投递三段式**：`deliveries prepare`（sheaf 固定 payload+资产+账号）→
  `as wechatoa article import`（终稿 MD+图集交 wechatoa 文章域：建文+资产上传，
  封面走 `--cover`+`--cover-logical-path` 完整冻结路径）→ `deliveries reconcile`
  （提交 article_receipt 回执，**服务端读回平台快照核对后才 synced**；unknown=安全
  降级，勿盲目重新建稿）。
- **账号边界**：平台账号（公众号）增删改在 wechatoa 工作台；sheaf 只读画像。

## 前置条件

```bash
as +me                      # 已登录（未登录先 as +connect 或 as auth login）
as wechatoa accounts list   # 拿本人目标公众号 account-id（UUID），不必是默认账号
as --json wechatoa accounts verify <accountId> # 必须 ok=true；占位号不可交稿
as wechatoa article list --limit 20 --offset 0  # 只读列表；JSON 含可见文章 total（可 null）
```

完整示例命令最低要求 CLI 0.6.38（含 article list/get）；整包安装及 --target 需 CLI 0.6.40。
账号预检会访问微信官方接口，超时/限流/IP 白名单故障须恢复后再运行全旅程；不自动切换其他账号。

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
#    图片引用必须在确认变体版本之前写进正文（assets/<文件名>；文件名含空格
#    用 ![配图](<assets/文件 名>) 包裹形态）——冻结后不再改正文，冻结
#    contentSha256 覆盖的就是这份含图引用的终稿字节
as sheaf variants create --project-id <projectId> --master-version-id <masterVersionId> \
  --target wechatoa,<accountId> --target-platform wechat_oa --content-kind article --json
# → variantId + accountProfileVersionId
as sheaf variants version --variant-id <variantId> \
  --content-md "# 冻结标题（H1=标题原值）

正文…

![配图](assets/body.png)" \
  --master-version-id <masterVersionId> --profile-version-id <accountProfileVersionId> \
  --content-kind article --title "<同一冻结标题>" --json
# → variantVersionId（confirmed，可投递）

# 6. 资产集合：上传图片到 Files → set 建 revision 1 → reorder 挂图
#    （用户态上传走 general.image——sheaf.* purpose 仅 sheaf 服务可用；
#     绑定白名单允许 general.image/mint.image 复用，v2 §2.7）
as files upload cover.jpg --purpose general.image --json   # → file_id
as files upload body.png --purpose general.image --json    # → file_id
as sheaf assets set --variant-id <variantId> --variant-version-id <variantVersionId> --json
as sheaf assets reorder --variant-id <variantId> --asset-set-id <assetSetId> --base-revision 1 \
  --item cover,file=<coverFileId>,purpose=general.image --item content,file=<contentFileId>,purpose=general.image --json

# 7. 投递意图（v2 合同：只带 variantVersionId——目标继承 confirmed 版本，
#    交稿动作由目标服务决定；输出冻结材料 renderedContent/payloadAssets）
as sheaf deliveries prepare --variant-version-id <variantVersionId> --json
# renderedContent.contentRef=变体版本（结构化引用）：正文经版本链取回
# （--json 双形状：sheaf 各 list 返回裸数组，勿假设 {items} 信封）
as sheaf variants list --variant-id <variantId> --json   # → 找 id==contentRef 的 contentMd/contentSha256
# payloadAssets 里的图片 fileId 随时可取回（Files，按当前用户授权）。
# 注意：冻结 payloadAssets 只有 slot/fileId/fileSha256——不含文件名；证据对位
# 基准=Files 元数据里的原文件名（组装 assets/ 时用上传时的原件名即天然一致，
# 重下载场景先 GET /v1/files/{id} 查 filename 再命名落盘）
as files download <coverFileId> --output assets/<原文件名>   # 文件名=原名（logicalPath 对位）

# 8. 交稿 wechatoa 文章域（终稿 MD+图集 → article import 建文+资产上传）→ 回执核对
#    v2 证据唯一形态=article_receipt（文章创建+资产上传结果；发布状态在
#    wechatoa 侧查询——as wechatoa article prepare/preview/publish，sheaf 只到核对）
#    第一个 wechatoa 写操作前：本地实算正文 SHA256 必须等于冻结 contentSha256，
#    不同即零写退出；图集按完整冻结 logicalPath 对位（不按下标/basename 串配），
#    同路径不同字节在首写前拒绝，封面兼正文图复用同 assetId
as wechatoa article import article.md --assets <文章根目录> --cover assets/<封面文件> \
  --cover-logical-path assets/<封面文件> --account-id <delivery.accountId> --json
# → articleId / assets[{logicalPath,assetId}] / coverAssetId
# 标题对齐是防御性保留：正常 sheaf 冻结链已 trim 标题，通常不触发本分支；
# 不能据此假设所有独立/历史文章标题都已 trim，三方仍精确比较实际完整值。
# 比较锚点是 delivery.renderedContent.title（冻结完整值）；平台实际标题与报告
# 标题分别对比它。例如冻结="标题"、平台="  标题  "，仅改回执标题仍失败。
# 不能一概认定带空白的历史文章失败，须看该投递的冻结值是否与实际值一致。
# 实际标题不一致时在交稿阶段按冻结完整值对齐，或建新版本/新投递；重核零回写。
# 正文 H1=冻结标题（import 按 H1 推导、首尾空白会被 trim）；冻结
# 标题含首尾空格时用 article update 按冻结原值 PATCH（仅交稿期；重核零回写）：
as wechatoa article update <articleId> --title "<冻结标题原值>" --json
as sheaf deliveries reconcile --delivery-id <delivery.id> \
  --article-id <articleId> --title "<冻结标题>" --markdown-sha256 <变体版本 contentSha256> \
  --asset slot=cover,logical-path=assets/<封面名>,asset-id=<coverAssetId>,sha256=<文件哈希> \
  --asset slot=content,logical-path=assets/<配图名>,asset-id=<assetId>,sha256=<文件哈希> --json
# asset-id=article import 返回的文章域 assetId；封面用 coverAssetId，绝不能用
# payloadAssets[].fileId / Files 上传 fileId 代替。sha256=源图字节，禁 preparedSha256。
# HTTP 200 ≠ 核验通过；failed 退出码为 1，unknown 可能退出 0。须解析 JSON，
# 要求 synced + articleId + verification.method/attemptId/checkedAt/contentVersion 齐全。
# → synced（服务端读回 wechatoa 平台实际快照核对通过——标题/正文哈希/资产逐位；
#   完成门=status synced+articleId 为本次交稿 ID+verification 四字段齐备）；
#   unknown=安全降级（读回暂不可得），稍后重跑 reconcile；
#   failed=evidence_mismatch（证据与冻结材料不符——核对标题/哈希/资产对位）；
#   failed=article_not_accessible（文章不存在/跨租户——检查 articleId）；
#   unknown=article_verification_unavailable（内部服务故障——运维告警，非文章问题）
# 只读重核形态：省略全部回执参数、仅带新 --client-request-id（每次新生成）
as sheaf deliveries reconcile --delivery-id <deliveryId> --client-request-id <新键> --json
# → 不重复交稿、不动文章内容；结果 status + verification{method,attemptId,checkedAt,contentVersion}
# 迁移旧态：errorCode=evidence_requires_readback=旧自报 synced 待新读回重核（非失败）
```

## 中断续接（旅程任一步失败后）

每步产物都是 UUID，重跑对应命令即可续接（幂等键保护重复提交）：

- 母稿 409 → `as sheaf master get --project-id ...` 拿最新 draftVersion 重编辑；
- prepare 后中断 → `as sheaf deliveries get <intentId>` 找回意图与冻结材料，
  重下材料继续；
- 交稿后未核对 → 重跑 reconcile（同一 --client-request-id 幂等；证据须重新
  组装 article_receipt——articleId/标题/哈希/资产对位）；
- 变体版本要改 → 新建版本（旧版不可变），**再对新版本 `assets set` + `reorder`
  重挂资产**（资产集按版本绑定不继承——不重挂则 prepare 冻结空资产集且同版本
  幂等锁死，补图只能再换版本），最后对新版本 prepare；
- 已 synced 且已具成功、身份匹配的官方账号证据 → 吸收，保留原 verification，
  不代表刷新当前事实；缺官方证据的旧 synced 可用非空新 `--client-request-id`
  只读补核，服务端恢复报告、读回并落新 attempt，按结果 synced/failed/unknown。
  无键迟到报告仍吸收；摘要冲突/跨投递键拒绝优先。改稿走新变体版本+新投递。

## Skill 执行登记（可选但推荐）

Agent 宿主执行本工作流时登记到 sheaf（聊天历史不当事实源）：

```bash
as sheaf skills run --skill-id sheaf-workflow --manifest-version 1.0.10 \
  --host <宿主名> --external-run-id <宿主run ID> --input-ref project:<projectId> --json
# 每步完成后：
as sheaf skills report --run-id <runId> --step-id <stepId> --attempt-index 1 \
  --status-claim succeeded --outputs-ref <产物引用>
```

## 一键脚本（Node.js 跨平台入口）

`scripts/full-journey.mjs` 把上述八步串成可独立执行的 Node.js 脚本，仅依赖 Node >=22 与已安装的 CLI；不需要 Bash/WSL/Git Bash 或 Python：

```text
node scripts/full-journey.mjs --account <wechatoa账号UUID> --title "标题" --cover cover.jpg --content-image body.png
node scripts/full-journey.mjs --account <wechatoa账号UUID> --prepare-only
node scripts/full-journey.mjs --recheck-delivery-id <deliveryId>
```

以上入口不使用 Shell 续行符。更多参数见 `node scripts/full-journey.mjs --help`。
本版已在 Windows 实机与 Linux Node 22 容器验证；macOS 安装布局已模拟验证，实际 macOS runner 尚未执行，不将模拟称为实测。

全旅程在首个内容写入之前执行所选账号的官方预检，最终 reconcile 仍核验冻结账号，预检不替代最终判定。
`--prepare-only` 不做官方探测；`--recheck-delivery-id` 仅核对同一投递，不上传/建文/改文/发布，服务端可以记录核验 attempt/审计。
每次命令 stdout（含失败 JSON）、stderr 和退出码均分别保留为 `.json` / `.err` / `.exit-code`；失败不自动重建文章。

脚本同样幂等：每次运行创建新选题/项目（标题带时间戳）；重复运行不互相干扰。
退出码语义：0=旅程 synced（完成门全过；`--prepare-only` 的 0 仅表示已 prepare）；
非零=未达成（含 unknown/failed/缺核验摘要——JSON 与恢复指引保留在 workdir）。
图片引用在冻结前注入正文、冻结后零改写，资产按完整 logicalPath 对位并校验
源哈希，这些门禁内建在脚本里，人工逐步执行时按第 5/8 步注释同样处理。

## 常见错误对照

| 症状 | 原因 | 处理 |
|---|---|---|
| master edit 409 | If-Match 与当前 draftVersion 不匹配 | `as sheaf master get` 取新值重编辑 |
| variants create 422 | 母稿版本不是 confirmed / 账号未连接平台 | 先 master confirm；wechatoa accounts verify |
| assets reorder 409 | baseRevision 落后（已有新 revision） | `as sheaf assets set` 响应或重跑取最新 revision |
| reconcile → unknown | 核验依赖/微信超时、限流或出口白名单等暂不可用 | 恢复原因后以新键重核同一投递；勿盲目再次建稿 |
| target_account_not_accessible | 冻结公众号不可访问；文章可能已落库 | 整体投递仍未成功；accounts verify 同一账号，修复后重核，不重复 import |
| prepare 200（非 201） | 同业务唯一键返回原意图 | 正常幂等语义，用返回的意图继续 |
| 正文 SHA 校验失败 | 冻结后正文被改动/取回不一致 | 零写退出是保护：新建变体版本重新走链，不改冻结材料 |
| 同路径不同字节拒绝 | 两张图同名但内容不同（文件名碰撞） | 改名其一后重传，再走资产挂载与 prepare |
