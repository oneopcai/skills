#!/usr/bin/env bash
# =============================================================================
# sheaf-workflow：内容创作全旅程一键脚本（收藏→选题→项目→母稿→变体→资产→
# prepare→wechatoa 文章域交稿→reconcile 回执核对——v2 合同 article_receipt）。
#
# 冻结纪律：
#   - 图片引用在变体版本确认（variants version）之前写进正文；冻结后只按
#     contentRef 取回原始 UTF-8 字节交稿，不再改正文；
#   - 首个 wechatoa 写操作（article import）前本地实算正文 SHA256 必须等于
#     冻结 contentSha256，不同即零写退出；
#   - 资产按完整冻结 logicalPath 对位（不按下标/basename 串配）；同路径
#     不同字节/文件名碰撞在首个平台写之前拒绝；源哈希对 prepare 冻结的
#     payloadAssets[].fileSha256 校验；
#   - 标题按冻结原值交稿：正文 H1=冻结标题；含首尾空格的标题（H1 推导会
#     trim）在交稿期用 wechatoa article update --title 对齐冻结原值。
#     此为防御性保留：正常 sheaf 冻结标题已 trim，通常不触发；独立/历史
#     文章仍按其实际完整值比较，不能假设不存在首尾空白。
#
# 用法：
#   ./full-journey.sh --account <wechatoa账号UUID> [选项]
# 选项：
#   --account <uuid>       目标公众号账号 ID（as wechatoa accounts list 的 ID 列，
#                          全旅程必填；--recheck-delivery-id 模式不需要）
#   --url <url>            素材链接（缺省 https://example.com/sheaf-demo）
#   --title <title>        选题/文章标题（缺省 "sheaf 旅程 <时间戳>"）
#   --cover <file>         封面图 jpg/png（缺省生成 1x1 占位 PNG）
#   --content-image <file> 正文图（缺省生成 1x1 占位 PNG；可多次）
#   --workdir <dir>        工作目录（默认 mktemp，保留全部中间产物）
#   --prepare-only         到 prepare 为止（取回并校验冻结正文后停止；不交稿
#                          wechatoa、不 reconcile——退出码 0 仅表示已 prepare，
#                          本终点不是 synced）
#   --recheck-delivery-id <id>
#                          只读重核模式：仅调用 reconcile（省略回执、新
#                          clientRequestId 由脚本生成），不创建新内容/投递意图、
#                          不上传 Files、不 import/update/publish；服务端可记核验 attempt/审计。
#
# 完成门（退出码 0 的唯一形态，--prepare-only 除外）：status=synced、返回
# articleId 等于本次交稿 ID、verification.method=wechatoa_article_readback、
# attemptId/checkedAt（带时区）/contentVersion（正整数）齐备。unknown/failed/
# 无核验摘要一律非零退出（JSON 与恢复指引保留，安全降级不当旅程成功）。
#
# 依赖：as（@oneopcai/agentschool-cli ≥0.6.38）已登录；node ≥22（JSON 提取）。
# 幂等性：每次运行创建新选题/项目（标题带时间戳）；写操作幂等键带运行序号，
# 同一次运行内重试安全。
# =============================================================================
set -euo pipefail

usage() {
  cat <<'USAGE'
用法：full-journey.sh --account <wechatoa账号UUID> [选项]
      full-journey.sh --recheck-delivery-id <投递UUID> [--workdir <dir>]
  --account <uuid>       目标公众号 ID；全旅程先官方验证，不自动换默认号
  --url <url>            素材链接
  --title <title>        文章标题
  --cover <file>         封面图 jpg/png
  --content-image <file> 正文图；可多次
  --workdir <dir>        保留 JSON / stderr / exit-code 及续接材料
  --prepare-only        仅冻结材料；未探测官方账号、未交稿、未核验，非 synced
  --recheck-delivery-id <id>
                        仅 reconcile；不上传、不 import/update/publish
  --help / -h           显示帮助
依赖：CLI >=0.6.38，Node >=22。微信草稿箱发布属于独立动作。
USAGE
}

# ── 参数解析 ────────────────────────────────────────────────────────────────
ACCOUNT=""
URL="https://example.com/sheaf-demo"
TITLE=""
COVER=""
CONTENT_IMAGES=()
WORKDIR=""
PREPARE_ONLY=0
RECHECK_DELIVERY_ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --account) ACCOUNT="${2:?}"; shift 2 ;;
    --url) URL="$2"; shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    --cover) COVER="$2"; shift 2 ;;
    --content-image) CONTENT_IMAGES+=("$2"); shift 2 ;;
    --workdir) WORKDIR="$2"; shift 2 ;;
    --prepare-only) PREPARE_ONLY=1; shift ;;
    --recheck-delivery-id) RECHECK_DELIVERY_ID="${2:?}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "✗ 未知参数：$1（--help 查看用法）" >&2; exit 2 ;;
  esac
done
if [ "$PREPARE_ONLY" = 1 ] && [ -n "$RECHECK_DELIVERY_ID" ]; then
  echo "✗ --prepare-only 与 --recheck-delivery-id 是两种互斥模式，不可同用" >&2
  exit 2
fi
if [ -z "$ACCOUNT" ] && [ -z "$RECHECK_DELIVERY_ID" ]; then
  echo "✗ 缺少 --account <wechatoa账号UUID>（as wechatoa accounts list 的 ID 列；只读重核用 --recheck-delivery-id，不需要账号）" >&2
  exit 2
fi
if [ -n "$ACCOUNT" ] && [[ ! "$ACCOUNT" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
  echo "✗ --account 须为 accounts list 返回的 UUID" >&2
  exit 2
fi
command -v node >/dev/null && command -v as >/dev/null || { echo "✗ 需要 Node >=22 与 CLI >=0.6.38" >&2; exit 1; }
CLI_VERSION="$(as --version)"
node -e '
  const s=process.argv[1].trim(), m=/^v?(\d+)\.(\d+)\.(\d+)$/.exec(s);
  const p=m?.slice(1).map(Number);
  if(Number(process.versions.node.split(".")[0])<22 || !p || !(p[0]>0 || p[1]>6 || (p[1]===6 && p[2]>=38))){
    console.error("✗ 需要 CLI >=0.6.38、Node >=22；当前 CLI="+s); process.exit(1);
  }
' "$CLI_VERSION"
STAMP="$(date +%Y%m%d-%H%M%S)"
RUN="sheaf-${STAMP}-$$"
if [ -z "$TITLE" ] && [ -z "$RECHECK_DELIVERY_ID" ]; then TITLE="sheaf 旅程 ${STAMP}"; fi

log()  { printf '\n== %s ==\n' "$*" >&2; }
step() { printf '  ✓ %s\n' "$*" >&2; }

# JSON 提取：stdin ← as --json 输出；$1 = 取值表达式（如 ".capture.sourceId"）
jget() {
  local expr="$1"
  node -e "
    let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{
      let v;try{v=JSON.parse(s)}catch(e){console.error('✗ 非 JSON 输出：'+s.slice(0,300));process.exit(1)}
      const out=eval('v'+process.argv[1]);
      if(out===undefined||out===null){console.error('✗ JSON 取值失败：'+process.argv[1]+' ← '+s.slice(0,300));process.exit(1)}
      console.log(typeof out==='object'?JSON.stringify(out):out);
    });" "$expr"
}
# 运行 as --json：非零退出也先保留 stdout JSON、stderr 与真实退出码。
# 用法：asj <标签> <as 子命令与参数...>（如 asj step1 sheaf captures add --url ...）
asj() {
  local tag="$1"; shift
  local rc=0
  as --json "$@" >"${WORKDIR}/${tag}.json" 2>"${WORKDIR}/${tag}.err" || rc=$?
  printf '%s\n' "$rc" >"${WORKDIR}/${tag}.exit-code"
  if [ "$rc" -ne 0 ]; then
    cat "${WORKDIR}/${tag}.err" >&2
    node -e '
      try {
        const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
        console.error("✗ status="+(d.status??"-")+" errorCode="+(d.errorCode??"-")+" articleId="+(d.articleId??"-"));
        if(d.errorCode==="target_account_not_accessible") console.error("  文章可能已落库；冻结公众号不可访问，整体投递未成功。修复账号后重核同一投递，不重复 import。");
      } catch { /* Raw stdout/stderr remain on disk, including transport errors. */ }
    ' "${WORKDIR}/${tag}.json" >&2
    echo "✗ 步骤失败：${tag}，exit=${rc}；JSON/stderr/exit-code 存于 ${WORKDIR}/${tag}.*" >&2
    local did="${DELIVERY_ID:-${RECHECK_DELIVERY_ID:-}}"
    if [ -n "$did" ]; then fail_guidance "$did"; fi
    return "$rc"
  fi
  cat "${WORKDIR}/${tag}.json"
}
sha256_of() {
  node -e 'const fs=require("fs"),c=require("crypto");console.log(c.createHash("sha256").update(fs.readFileSync(process.argv[1])).digest("hex"));' "$1"
}
uuid() { node -e 'console.log(crypto.randomUUID())'; }

# 完成门（公共契约 §五）：$1=reconcile JSON 文件；$2=期望 articleId（空=只读
# 重核，仅要求非空）。全部门槛通过时输出 method|attemptId|checkedAt|
# contentVersion 并返回 0；任何一项不满足打印失败清单并返回 1。
check_result() {
  local json_file="$1" expect_article="$2"
  node -e '
    const fs=require("fs");
    const d=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
    const expect=process.argv[2]||"";
    const errs=[];
    if(d.status!=="synced") errs.push("status="+(d.status??"null")+"（非 synced）");
    const art=d.articleId??"";
    if(expect){ if(art!==expect) errs.push("articleId="+art+" ≠ 本次交稿 "+expect); }
    else if(!art){ errs.push("articleId 缺失"); }
    const v=d.verification;
    if(!v||typeof v!=="object"){ errs.push("verification 缺失（无有效读回摘要）"); }
    else{
      if(v.method!=="wechatoa_article_readback") errs.push("verification.method="+(v.method??"null"));
      if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v.attemptId??"")) errs.push("attemptId 无效");
      if(!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})$/.test(v.checkedAt??"")) errs.push("checkedAt 缺时区或非法");
      if(!Number.isInteger(v.contentVersion)||v.contentVersion<1) errs.push("contentVersion 非正整数");
    }
    if(errs.length){ console.error("✗ 完成门未通过："+errs.join("；")); process.exit(1); }
    console.log(v.method+"|"+v.attemptId+"|"+v.checkedAt+"|"+v.contentVersion);
  ' "$json_file" "$expect_article"
}
# 完成门失败的统一恢复指引：$1=deliveryId
fail_guidance() {
  echo "  排查：as sheaf deliveries get $1" >&2
  echo "  只读重核（零平台写，可记录核验 attempt/审计）：as sheaf deliveries reconcile --delivery-id $1 --client-request-id <新生成键>" >&2
  echo "  原始 JSON 与全部中间产物见 workdir" >&2
}

# ── 只读重核模式（--recheck-delivery-id；仅 reconcile，零平台写） ───────────
if [ -n "$RECHECK_DELIVERY_ID" ]; then
  if [ -z "$WORKDIR" ]; then WORKDIR="$(mktemp -d -t "${RUN}.XXXXXX")"; else mkdir -p "$WORKDIR"; fi
  log "只读重核（delivery=${RECHECK_DELIVERY_ID}，workdir=${WORKDIR}）"
  RECHECK_KEY="$(uuid)"
  RECONCILE="$(asj recheck sheaf deliveries reconcile --delivery-id "$RECHECK_DELIVERY_ID" --client-request-id "$RECHECK_KEY")"
  if ! VERIF="$(check_result "${WORKDIR}/recheck.json" "")"; then
    cat "${WORKDIR}/recheck.json" >&2 || true
    fail_guidance "$RECHECK_DELIVERY_ID"
    exit 1
  fi
  IFS='|' read -r V_METHOD V_ATTEMPT V_CHECKED V_VERSION <<<"$VERIF"
  step "clientRequestId=${RECHECK_KEY}"
  step "verification：method=${V_METHOD} attemptId=${V_ATTEMPT} checkedAt=${V_CHECKED} contentVersion=${V_VERSION}"
  log "只读重核返回 synced（以上为返回摘要的核验时点；官方证据吸收保留旧 attempt，历史补核可产生新 attempt，请与重核前摘要比较）"
  exit 0
fi

# ── 工作目录与素材准备 ──────────────────────────────────────────────────────
if [ -z "$WORKDIR" ]; then WORKDIR="$(mktemp -d -t "${RUN}.XXXXXX")"; else mkdir -p "$WORKDIR"; fi
# 1x1 透明 PNG（67 字节）：未提供图片时的占位（本地栈验证用；生产建议真图）
PNG_1X1="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
if [ -z "$COVER" ]; then
  COVER="${WORKDIR}/cover.png"
  printf '%s' "$PNG_1X1" | base64 -d > "$COVER"
fi
if [ ${#CONTENT_IMAGES[@]} -eq 0 ]; then
  CONTENT_IMAGES=("${WORKDIR}/content-1.png")
  printf '%s' "$PNG_1X1" | base64 -d > "${CONTENT_IMAGES[0]}"
fi
# 文件名进入冻结 logicalPath（assets/<名>）与 MD 引用：禁字符在此前置拒绝
for imgfile in "$COVER" "${CONTENT_IMAGES[@]}"; do
  [ -f "$imgfile" ] || { echo "✗ 图片文件不存在：${imgfile}" >&2; exit 1; }
  case "$(basename "$imgfile")" in
    *[[:cntrl:]]*|*'>'*|*'?'*|*'#'*|*'\'*|*'`'*)
      echo "✗ 图片文件名含禁用字符（> ? # \\ 反引号/控制符，logicalPath 不支持）：$(basename "$imgfile")" >&2
      exit 1 ;;
  esac
done

log "sheaf 全旅程开始（workdir=${WORKDIR}）"

# ── 0. 登录自检 ─────────────────────────────────────────────────────────────
log "0/8 登录与账号自检"
as +me > /dev/null 2>&1 || { echo "✗ 未登录：先 as +connect 或 as auth login" >&2; exit 1; }
step "已登录"
if [ "$PREPARE_ONLY" = 0 ]; then
  asj account-verify wechatoa accounts verify "$ACCOUNT" > /dev/null
  node -e '
    const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
    if(d.ok!==true){
      console.error("✗ 目标公众号未通过官方连通性预检：reason="+(d.reason??"unavailable")+" errcode="+(d.errcode??"-"));
      console.error("  确认该账号为本人可访问的真实公众号；占位测试号不可用。超时/限流/白名单问题恢复后再试；尚未创建内容、上传或交稿。");
      process.exit(1);
    }
  ' "${WORKDIR}/account-verify.json"
  step "目标公众号官方预检通过（最终 reconcile 仍按冻结账号再次核验）"
fi

# ── 1. 收藏素材 ─────────────────────────────────────────────────────────────
log "1/8 收藏素材"
CAPTURE="$(asj capture sheaf captures add --url "$URL" --client-request-id "${RUN}-cap")"
SOURCE_ID="$(printf '%s' "$CAPTURE" | jget '.capture.sourceId')"
step "capture=$(printf '%s' "$CAPTURE" | jget '.capture.id') source=${SOURCE_ID}"

# ── 2. 选题 + 评估 ──────────────────────────────────────────────────────────
log "2/8 选题与评估"
TOPIC="$(asj topic sheaf topics create --title "$TITLE" --source-ids "$SOURCE_ID")"
TOPIC_ID="$(printf '%s' "$TOPIC" | jget '.id')"
asj assess sheaf topics assess "$TOPIC_ID" --rule-version v1 --score 85 > /dev/null
step "topic=${TOPIC_ID}"

# ── 3. 项目 ─────────────────────────────────────────────────────────────────
log "3/8 创建项目"
PROJECT="$(asj project sheaf projects create --topic-id "$TOPIC_ID" --title "$TITLE")"
PROJECT_ID="$(printf '%s' "$PROJECT" | jget '.id')"
step "project=${PROJECT_ID}"

# ── 4. 母稿：编辑（CAS 首次 0）→ 确认 ──────────────────────────────────────
log "4/8 母稿编辑与确认"
cat > "${WORKDIR}/master.md" <<EOF
# ${TITLE}

素材链接：${URL}

## 正文

这是经 sheaf 工作流生成的母稿正文。确认后固化为不可变版本，
变体在此基础上按账号画像改写。
EOF
DRAFT="$(asj master-edit sheaf master edit --project-id "$PROJECT_ID" --title "$TITLE" --content-file "${WORKDIR}/master.md" --if-match 0)"
DRAFT_VER="$(printf '%s' "$DRAFT" | jget '.draftVersion')"
MASTERVER="$(asj master-confirm sheaf master confirm --project-id "$PROJECT_ID" --if-match "$DRAFT_VER" --idempotency-key "${RUN}-mc")"
MASTER_VERSION_ID="$(printf '%s' "$MASTERVER" | jget '.id')"
step "draftVersion=${DRAFT_VER} masterVersion=${MASTER_VERSION_ID}"

# ── 5. 变体：create（target 物化）→ version（直建 confirmed） ───────────────
# 图片引用在此步写进正文（冻结前完成）：正文 H1=冻结标题；图片引用
# assets/<文件名> 按先后对应 content 槽；文件名含空格/括号用 <…> 包裹形态
log "5/8 变体与账号稿（图片引用随正文一并冻结）"
VARIANT="$(asj variant sheaf variants create --project-id "$PROJECT_ID" --master-version-id "$MASTER_VERSION_ID" \
  --target "wechatoa,${ACCOUNT}" --target-platform wechat_oa --content-kind article)"
VARIANT_ID="$(printf '%s' "$VARIANT" | jget '.id')"
PROFILE_VERSION_ID="$(printf '%s' "$VARIANT" | jget '.accountProfileVersionId')"
md_image_ref() { # assets/<名> → MD 引用（文件名含空格/括号用 <…> 形态）
  local ref="assets/$(basename "$1")"
  case "$ref" in
    *[[:space:]]*|*'('*) printf '![配图](<%s>)' "$ref" ;;
    *) printf '![配图](%s)' "$ref" ;;
  esac
}
{
  printf '# %s\n\n' "$TITLE"
  printf '母稿版本 %s 按账号画像改写后的账号稿：标题更抓人、段落更短、口语化收尾引导在看/转发。\n' "$MASTER_VERSION_ID"
  for img in "${CONTENT_IMAGES[@]}"; do
    printf '\n%s\n' "$(md_image_ref "$img")"
  done
} > "${WORKDIR}/variant.md"
VVERSION="$(asj variant-version sheaf variants version --variant-id "$VARIANT_ID" \
  --content-file "${WORKDIR}/variant.md" --title "$TITLE" \
  --master-version-id "$MASTER_VERSION_ID" --profile-version-id "$PROFILE_VERSION_ID" \
  --content-kind article --client-request-id "${RUN}-vv")"
VARIANT_VERSION_ID="$(printf '%s' "$VVERSION" | jget '.id')"
step "variant=${VARIANT_ID} version=${VARIANT_VERSION_ID}（$(printf '%s' "$VVERSION" | jget '.status')，正文含 ${#CONTENT_IMAGES[@]} 个图片引用）"

# ── 6. 资产集合：上传图片 → set → reorder 挂图 ──────────────────────────────
log "6/8 资产集合"
# 用户态上传走 general.image（sheaf.* purpose 仅 sheaf 服务可用——v2 白名单
# 明示资产绑定可合法复用 general.image/mint.image）
COVER_FILE_ID="$(asj upload-cover files upload "$COVER" --purpose general.image | jget '.file_id')"
CONTENT_FILE_IDS=()
for img in "${CONTENT_IMAGES[@]}"; do
  CONTENT_FILE_IDS+=("$(asj upload-content files upload "$img" --purpose general.image | jget '.file_id')")
done
ASET="$(asj assets-set sheaf assets set --variant-id "$VARIANT_ID" --variant-version-id "$VARIANT_VERSION_ID")"
ASET_ID="$(printf '%s' "$ASET" | jget '.id')"
ASET_REV="$(printf '%s' "$ASET" | jget '.revision')"
REORDER_ARGS=(--variant-id "$VARIANT_ID" --asset-set-id "$ASET_ID" --base-revision "$ASET_REV" --item "cover,file=${COVER_FILE_ID},purpose=general.image")
for fid in "${CONTENT_FILE_IDS[@]}"; do REORDER_ARGS+=("--item" "content,file=${fid},purpose=general.image"); done
ASET2="$(asj assets-reorder sheaf assets reorder "${REORDER_ARGS[@]}")"
step "assetSet=$(printf '%s' "$ASET2" | jget '.id') revision=$(printf '%s' "$ASET2" | jget '.revision')（cover×1 content×${#CONTENT_FILE_IDS[@]}）"

# ── 7. 投递意图 prepare（冻结材料）+ 终稿取回与完整性校验 ──────────────────
log "7/8 投递意图 prepare"
# v2 合同：prepare 只带 variantVersionId（目标继承 confirmed 版本；交稿动作由
# 目标服务决定——无 operationKind）；幂等键缺省自动生成
DELIVERY="$(asj delivery sheaf deliveries prepare --variant-version-id "$VARIANT_VERSION_ID")"
DELIVERY_ID="$(printf '%s' "$DELIVERY" | jget '.id')"
CONTENT_REF="$(printf '%s' "$DELIVERY" | jget '.renderedContent.contentRef')"
ARTICLE_TITLE="$(printf '%s' "$DELIVERY" | jget '.renderedContent.title')"
# contentRef=变体版本（结构化引用）：正文经版本链取回——精确匹配 contentRef，
# 版本未命中直接拒绝（不兜底取首个）；--json 双形状：sheaf 各 list 返回裸
# 数组，勿假设 {items} 信封
as --json sheaf variants list --variant-id "$VARIANT_ID" > "${WORKDIR}/variant-versions.json"
node -e '
  const fs=require("fs");
  const d=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
  const arr=Array.isArray(d)?d:(d.items||[]);
  const v=arr.find(it=>it&&it.id===process.argv[2]);
  if(!v){console.error("✗ 精确版本未命中：contentRef="+process.argv[2]+" 不在变体版本列表（"+arr.length+" 条）——拒绝继续，不兜底取首个");process.exit(1)}
  const md=v.contentMd??"";
  if(!md){console.error("✗ 正文取回为空（contentRef="+process.argv[2]+"）");process.exit(1)}
  if(!/^[0-9a-f]{64}$/i.test(v.contentSha256??"")){console.error("✗ 变体版本缺 contentSha256（reconcile 证据必需）");process.exit(1)}
  fs.writeFileSync(process.argv[3], md);
  fs.writeFileSync(process.argv[4], v.contentSha256);
' "${WORKDIR}/variant-versions.json" "$CONTENT_REF" "${WORKDIR}/article.md" "${WORKDIR}/content.sha256"
FROZEN_SHA="$(cat "${WORKDIR}/content.sha256")"
step "intent=${DELIVERY_ID} contentRef=${CONTENT_REF} markdownSha256=${FROZEN_SHA:0:12}… assetSetRevision=$(printf '%s' "$DELIVERY" | jget '.assetSetRevision')"

if [ "$PREPARE_ONLY" = 1 ]; then
  log "完成（--prepare-only：已到 prepare，冻结正文已取回；未交稿 wechatoa、未 reconcile——本终点不是 synced）"
  printf '  材料 workdir=%s（article.md=冻结原文字节，content.sha256=%s）\n' "$WORKDIR" "$FROZEN_SHA" >&2
  exit 0
fi

# ── 8. wechatoa 文章域交稿 → reconcile 回执核对（v2：article_receipt） ──────
log "8/8 wechatoa 文章域交稿与回执核对"
# 图集组装：assets/<原名> 按完整 logicalPath 对位；同路径不同字节/文件名
# 碰撞在首个平台写之前拒绝；同路径同字节（封面兼正文图/重复引用）合法复用
ARTICLE_ROOT="${WORKDIR}/article-root"
mkdir -p "${ARTICLE_ROOT}/assets"
cp "${WORKDIR}/article.md" "${ARTICLE_ROOT}/article.md"
# payloadAssets 源哈希表（fileId → fileSha256；按 fileId 对位不依赖数组顺序）
node -e '
  const fs=require("fs");
  const d=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
  const rows=(d.payloadAssets??[]).map(a=>a.fileId+"\t"+(a.fileSha256??""));
  fs.writeFileSync(process.argv[2], rows.join("\n")+(rows.length?"\n":""));
' "${WORKDIR}/delivery.json" "${WORKDIR}/payload-hashes.tsv"
# 槽位清单（cover 先、content 按 MD 顺序）+ 冻结哈希校验 + 碰撞拒绝
SLOT_LIST="${WORKDIR}/slots.tsv"
: > "$SLOT_LIST"
verify_slot() { # $1=slot $2=本地文件 $3=fileId
  local slot="$1" src="$2" fid="$3" name sha frozen
  name="$(basename "$src")"
  sha="$(sha256_of "$src")"
  if [ ! -f "${ARTICLE_ROOT}/assets/${name}" ]; then
    cp "$src" "${ARTICLE_ROOT}/assets/${name}"
  elif [ "$sha" != "$(sha256_of "${ARTICLE_ROOT}/assets/${name}")" ]; then
    echo "✗ 同路径不同字节：assets/${name} 已由不同源文件占用（文件名碰撞）——首个平台写之前拒绝" >&2
    exit 1
  fi
  if ! grep -qF "${fid}$(printf '\t')" "${WORKDIR}/payload-hashes.tsv"; then
    echo "✗ 冻结资产集缺 ${slot} 槽文件（fileId=${fid}，assets/${name}）——prepare 冻结材料与本地图集不一致，拒绝交稿" >&2
    exit 1
  fi
  frozen="$(awk -F '\t' -v fid="$fid" '$1==fid{print $2; exit}' "${WORKDIR}/payload-hashes.tsv")"
  if [ -n "$frozen" ] && [ "$frozen" != "$sha" ]; then
    echo "✗ 源哈希不符：${slot} 槽 assets/${name} 本地 sha256=${sha} ≠ prepare 冻结 fileSha256=${frozen}——首个平台写之前拒绝" >&2
    exit 1
  fi
  printf '%s\t%s\t%s\n' "$slot" "assets/${name}" "$sha" >> "$SLOT_LIST"
}
verify_slot cover "$COVER" "$COVER_FILE_ID"
i=0
for img in "${CONTENT_IMAGES[@]}"; do
  verify_slot content "$img" "${CONTENT_FILE_IDS[$i]}"
  i=$((i+1))
done
step "图集就绪（cover×1 content×${#CONTENT_IMAGES[@]}，logicalPath 对位+源哈希校验通过）"
# 首个 wechatoa 写操作前的正文完整性门：本地实算 SHA 必须等于冻结 contentSha256
LOCAL_MD_SHA="$(sha256_of "${ARTICLE_ROOT}/article.md")"
if [ "$LOCAL_MD_SHA" != "$FROZEN_SHA" ]; then
  echo "✗ 正文完整性校验失败：本地实算 sha256=${LOCAL_MD_SHA} ≠ 冻结 contentSha256=${FROZEN_SHA}——零写退出（不交稿 wechatoa）" >&2
  exit 1
fi
COVER_BASE="$(basename "$COVER")"
IMPORT="$(asj import wechatoa article import "${ARTICLE_ROOT}/article.md" --assets "$ARTICLE_ROOT" \
  --cover "${ARTICLE_ROOT}/assets/${COVER_BASE}" --cover-logical-path "assets/${COVER_BASE}" --account-id "$ACCOUNT")"
ARTICLE_ID="$(printf '%s' "$IMPORT" | jget '.articleId')"
COVER_ASSET_ID="$(printf '%s' "$IMPORT" | jget '.coverAssetId')"
step "articleId=${ARTICLE_ID} assets=$(printf '%s' "$IMPORT" | jget '.assets.length')+封面"

# 标题对齐：正文 H1=冻结标题，import 按 H1 推导（首尾空白会被 trim）；
# 冻结标题含首尾空格时在交稿期用 article update --title 对齐冻结原值
# （只读重核零回写，不做标题 PATCH）
if [[ "$ARTICLE_TITLE" =~ ^[[:space:]]|[[:space:]]$ ]]; then
  asj title-align wechatoa article update "$ARTICLE_ID" --title "$ARTICLE_TITLE" > /dev/null
  step "冻结标题含首尾空白——article update --title 已按冻结原值对齐"
fi

# 组装 article_receipt 证据：按完整冻结 logicalPath 从 import 返回资产中取
# assetId（响应数组顺序无关）；封面槽用 coverAssetId；封面兼正文图/重复
# 引用同路径同哈希复用同 assetId，槽位全部保留
EVIDENCE_LIST="${WORKDIR}/evidence-assets.txt"
if ! node -e '
  const fs=require("fs");
  const imp=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
  const byPath=new Map();
  for(const a of (imp.assets??[])){ if(a&&a.logicalPath&&a.assetId) byPath.set(a.logicalPath,a.assetId); }
  const lines=fs.readFileSync(process.argv[2],"utf8").split("\n").filter(Boolean);
  const out=[];
  for(const line of lines){
    const parts=line.split("\t");
    const slot=parts[0], lp=parts[1], sha=parts.slice(2).join("\t");
    let id;
    if(slot==="cover"){ id=imp.coverAssetId??""; }
    else{ id=byPath.get(lp)??""; }
    if(!id){ console.error("✗ import 返回资产中找不到 logicalPath="+lp+"（"+slot+" 槽）——无法组装回执证据"); process.exit(1); }
    out.push("slot="+slot+",logical-path="+lp+",asset-id="+id+",sha256="+sha);
  }
  process.stdout.write(out.join("\n")+(out.length?"\n":""));
' "${WORKDIR}/import.json" "$SLOT_LIST" > "$EVIDENCE_LIST"; then
  echo "✗ 回执证据组装失败（按 logicalPath 对位 import 资产未命中）" >&2
  fail_guidance "$DELIVERY_ID"
  exit 1
fi
mapfile -t EVIDENCE_ASSETS < "$EVIDENCE_LIST"
EVIDENCE_ARGS=(--delivery-id "$DELIVERY_ID" --article-id "$ARTICLE_ID" --title "$ARTICLE_TITLE" --markdown-sha256 "$FROZEN_SHA")
for ev in "${EVIDENCE_ASSETS[@]}"; do EVIDENCE_ARGS+=("--asset" "$ev"); done
RECONCILE="$(asj reconcile sheaf deliveries reconcile "${EVIDENCE_ARGS[@]}")"
if ! VERIF="$(check_result "${WORKDIR}/reconcile.json" "$ARTICLE_ID")"; then
  cat "${WORKDIR}/reconcile.json" >&2 || true
  fail_guidance "$DELIVERY_ID"
  exit 1
fi
IFS='|' read -r V_METHOD V_ATTEMPT V_CHECKED V_VERSION <<<"$VERIF"

log "旅程完成：${TITLE}"
printf '  选题 topic=%s\n  项目 project=%s\n  母稿 masterVersion=%s\n  变体版本 variantVersion=%s\n  投递 intent=%s（synced，article=%s）\n  核验 verification：method=%s attemptId=%s checkedAt=%s contentVersion=%s\n  材料 workdir=%s\n' \
  "$TOPIC_ID" "$PROJECT_ID" "$MASTER_VERSION_ID" "$VARIANT_VERSION_ID" "$DELIVERY_ID" "$ARTICLE_ID" \
  "$V_METHOD" "$V_ATTEMPT" "$V_CHECKED" "$V_VERSION" "$WORKDIR" >&2
exit 0
