---
name: wechatoa-workflow
version: 1.2.2
description: "公众号图文发布工作流 skill —— Agent 产出标准含图 Markdown 与封面后，as wechatoa publish 一键发布到草稿箱（服务端模板渲染+封面必传）；需要分步编辑/预览/定版时用 as wechatoa article 命令组，发布统一走 as wechatoa publish 或 article publish --cover。当用户要『发图文到公众号』『一键发布 MD』『排版模板』『预览/发布 revision』时使用本技能。"
metadata:
  requires:
    bins: ["as"]
    node: ">=22"
  cliHelp: "as wechatoa publish --help"
  projectHome: "https://agentschool.me"
  scopeList:
    - article: 图文文章（MD+assets → 文章 → 不可变 revision）
    - assets: 配图资产（logicalPath 归一化，MD 图片节点定顺序）
    - preparations: 准备（压缩配图，accepted 异步自动轮询）
    - revisions: 不可变定版（canonical fragment、preview 只读投影）
    - publish: 发布到公众号草稿箱（幂等键稳定、unknown 不盲重试）
---

# Wechatoa 图文文章工作流（Markdown → 公众号草稿箱）

命令来自 npm 包 `@oneopcai/agentschool-cli`（统一发布面需 ≥0.6.25）。

**一键发布（主路径）**：`as wechatoa publish <md> --cover <封面图> [--template <模板名>] [--assets <文章根>]`
——服务端统一端点 markdown 模式：模板渲染 → 配图上传（超 2MB 自动压缩）→ 建稿草稿箱。
**封面必传**（微信硬性要求；不传直接报错，无任何兜底）。

**HTML 直发**：`as wechatoa publish --file <f.html> --cover <封面图> [--content-images <图...>]`
——自有排版 HTML 直入草稿箱；正文图按 HTML 中 `data-wx-image` 占位符顺序与 `--content-images`
入参顺序对位（超 2MB 服务端自动压缩）。与 `<md>` 互斥。

**分步编排（可选）**：`as wechatoa article import/update/prepare/preview` 建稿-定版-预览，
`article publish <revisionId> --cover <图>` 发布定版（内部同走统一端点）。
**模板管理**：`as wechatoa template list/save/delete/default`（用户级模板库；发布
`--template` 引用，不传用账户默认）。`as wechatoa draft publish` 已移除（统一入口=publish）。

权限：article 域读写需 `wechatoa.article.read` / `wechatoa.article.write`，
发布与模板需 `wechatoa.draft.publish` / 模板读写码（403 联系管理员开放）。

## 一、标准含图 Markdown 产出规范（Agent 写稿纪律）

**结构由 MD 决定，服务端只做忠实渲染**：

1. **图片节点定顺序**：正文图片按 MD 中 `![alt](相对路径)` 出现顺序即成稿顺序；
   不要用「放在开头/结尾」之类 placement 约定，改顺序=改 MD 节点顺序。
2. **不强加结构**：不要自动强加小标题、分节、封面位等结构元素。**可以**向用户
   建议小标题（"加一节 ## 实操步骤 会更清晰"），但用户不同意就不动稿。
3. **保留引语与事实**：原素材的引语（> 引用块）、数字、时间、人名等事实内容
   必须逐字保留；改写只发生在组织与衔接层，不吞事实。
4. **配图引用形态**：MD 图片引用**必须以 `assets/` 开头**（`![描述](assets/相对路径)`，
   与上传 logicalPath 精确一致；裸名/缺前缀在第一个变更请求前被拒绝，不自动补前缀）。
   远程 URL（http/…）、绝对路径、`..` 越界、含 `?`/`#`、引用式（`![alt][label]`）
   会被 import 拒绝（可解释错误）；远程图先下载进 assets 再引用。
5. **标题**：首个 `# 一级标题` 作为文章标题（1-200 字符）；没有 H1 时回退文件名。
6. **主题/全局参数不进 MD**：主题（minimal/tech/warm）、字号、行高、强调色属
   **文章设置**（settings），在 Website 文章设置面配置——MD 只承载内容与结构。

## 二、五命令旅程

```bash
as me                                   # 已登录（否则先 as +connect）
as wechatoa accounts list               # 拿公众号 account-id（UUID）

# 1. 导入：MD+assets → 文章（配图按 MD 顺序上传；返回 articleId）
#    幂等：同内容重复 import 复用既有文章（零重复建文）；--force 强制新建
#    --assets=含 assets/ 子目录的文章根（如 ./my-article 下有 assets/），不是 assets 目录本身
#    --cover=封面图（CLI ≥0.6.22）：上传为独立资产并设为文章封面——发布时优先使用；
#    不传 --cover 时发布回退「第一张配图」当封面（用户在意封面就必须显式给 --cover）
as wechatoa article import draft.md --assets ./my-article --cover cover.png \
  --account-id <UUID> --json
# → { articleId, title, contentVersion, assets: [{assetId, logicalPath}], coverAssetId }

# 2.（可选）迭代：改 MD 后携基线更新（--base-version 乐观并发，409 不覆盖；
#    省略则自动取服务端最新 contentVersion）
as wechatoa article update <articleId> --md draft-v2.md --json

# 3. 准备：压缩配图 → finalize 不可变 revision（accepted 异步自动轮询，
#    默认上限 120s，--timeout 秒可调）
as wechatoa article prepare <articleId> --json
# → { preparationId, status: "succeeded", revisionId, sourceVersion }

# 4. 预览：服务端 canonical fragment 的本地只读投影（临时 HTML 文件路径）
as wechatoa article preview <revisionId> --json
# → { htmlPath }   # 浏览器打开核对图文顺序与排版

# 5. 发布：revision → 公众号草稿箱（缺省键按 accountId+revisionId+intent
#    确定性派生——同语义同键，换账号/换 intent 自动换键）
as wechatoa article publish <revisionId> --account-id <UUID> \
  --intent-id <业务意图> --json
# → { action, mediaId, operationId, verify: { status: "matched" } }
```

**图文顺序验证法（CLI 导出再导入）**：对已发布/已有文章，把导出的普通 MD+
图片重新 `article import`，对比新旧 revision 的图片顺序——一致即图文顺序
无漂移。普通 MD+图片导出保证**内容/结构/图片顺序**三不变；**不**宣称携带全部
公众号样式（主题渲染、公众号私有排版属文章设置与服务端渲染，不在 MD 里）。

## 三、Website 预览与编辑边界

- Website 文章页**右栏是只读公众号预览**：展示 revision 的 canonical fragment
  渲染效果；首版**没有可视化编辑、没有 HTML 反写**——改内容一律改 MD 后
  `article update` + `article prepare`（新 revision）。
- 主题、字号、行高、强调色等**全局参数属文章设置**（settings），经 Website
  文章设置面调整，**不写回 MD**——MD 永远只承载内容与结构。
- CLI `article preview` 与 Website 右栏预览同源（同一 revision fragment），
  结论互通。

## 四、安全纪律（幂等 / 冲突 / unknown）

| 场景 | 行为 |
|---|---|
| publish 网络中断 | **结果未知 ≠ 失败**：不盲重试。缺省键按 accountId+revisionId+intent 确定性派生——换账号自动换键；重跑同一命令（同账号同 revision 同 intent）即同键重放原结果、不重复建稿；或到 mp.weixin.qq.com 草稿箱核对 |
| 自定义幂等键 | `--idempotency-key` 重试必须沿用同一键；同键+同意图+同载荷才重放（异意图/异载荷 409） |
| update 409 | 版本冲突=不覆盖；省略 `--base-version` 重跑（自动取服务端最新） |
| prepare failed | 带 failure_code/failure_message；修 MD 后重新 prepare（旧 revision 不可变不受影响） |
| 配图同名 | logicalPath 是完整归一化路径（`assets/a/x.png` ≠ `assets/b/x.png`），**不按 basename 猜**；封面独立命名 `assets/cover-<原名>`，与 MD 引用同名冲突前置拒绝 |
| revision 不可变 | 改稿=新 revision；publish 永远针对指定 revisionId |
| 封面 | **发布必传**（publish/article publish 的 --cover；微信硬性要求）——纯文字文章也必须给封面，无兜底 |
| 配图/封面超 2MB | 微信素材库图片硬限 2MB——`draft publish` 的正文图与封面、article 流水线的配图超限时**服务端自动压缩**（正文 wechat-content / 封面 wechat-cover 预设，CLI ≥0.6.22 发布结果逐张/逐张提示「🗜 已压缩 X → Y」）；压缩失败/服务不可达按 502/503、凭据链未放行按 403 报错，不静默降级 |

## 五、与 sheaf 工作流的关系

sheaf-workflow（收藏→选题→变体→投递建稿）面向**多账号变体投递**，建稿走
`as wechatoa draft publish`（HTML+封面直投草稿箱）。本技能面向**单篇图文文章的
MD 全生命周期**（导入/准备/预览/发布）。两条链共享 wechatoa 账号与草稿箱，按需
选用：变体矩阵走 sheaf，单篇图文走 article。
