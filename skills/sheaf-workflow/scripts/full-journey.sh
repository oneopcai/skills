#!/usr/bin/env bash
# =============================================================================
# sheaf-workflow：内容创作全旅程一键脚本（收藏→选题→项目→母稿→变体→资产→
# prepare→wechatoa 建稿→reconcile 回执核对）。
#
# 用法：
#   ./full-journey.sh --account <wechatoa账号UUID> [选项]
# 选项：
#   --account <uuid>       目标公众号账号 ID（as wechatoa accounts list 的 ID 列，必填）
#   --url <url>            素材链接（缺省 https://example.com/sheaf-demo）
#   --title <title>        选题/文章标题（缺省 "sheaf 旅程 <时间戳>"）
#   --cover <file>         封面图 jpg/png（缺省生成 1x1 占位 PNG）
#   --content-image <file> 正文图（缺省生成 1x1 占位 PNG；可多次）
#   --workdir <dir>        工作目录（默认 mktemp，保留全部中间产物）
#   --skip-publish         到 prepare 为止（不调 wechatoa、不 reconcile）
#
# 依赖：as（@oneopcai/agentschool-cli ≥0.7.0）已登录；node ≥22（JSON 提取）。
# 幂等性：每次运行创建新选题/项目（标题带时间戳）；写操作幂等键带运行序号，
# 同一次运行内重试安全。
# =============================================================================
set -euo pipefail

# ── 参数解析 ────────────────────────────────────────────────────────────────
ACCOUNT=""
URL="https://example.com/sheaf-demo"
TITLE=""
COVER=""
CONTENT_IMAGES=()
WORKDIR=""
SKIP_PUBLISH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --account) ACCOUNT="${2:?}"; shift 2 ;;
    --url) URL="$2"; shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    --cover) COVER="$2"; shift 2 ;;
    --content-image) CONTENT_IMAGES+=("$2"); shift 2 ;;
    --workdir) WORKDIR="$2"; shift 2 ;;
    --skip-publish) SKIP_PUBLISH=1; shift ;;
    *) echo "✗ 未知参数：$1（--help 查看用法）" >&2; exit 2 ;;
  esac
done
if [ -z "$ACCOUNT" ]; then
  echo "✗ 缺少 --account <wechatoa账号UUID>（as wechatoa accounts list 的 ID 列）" >&2
  exit 2
fi
STAMP="$(date +%Y%m%d-%H%M%S)"
RUN="sheaf-${STAMP}-$$"
if [ -z "$TITLE" ]; then TITLE="sheaf 旅程 ${STAMP}"; fi

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
# 运行 as --json 并落盘原始输出（排障用）；失败即停（错误信息由 as 打印）
# 用法：asj <标签> <as 子命令与参数...>（如 asj step1 sheaf captures add --url ...）
asj() {
  local tag="$1"; shift
  local out
  if ! out="$(as --json "$@" 2>"${WORKDIR}/${tag}.err")"; then
    cat "${WORKDIR}/${tag}.err" >&2
    echo "✗ 步骤失败：${tag}（stderr 存于 ${WORKDIR}/${tag}.err）" >&2
    exit 1
  fi
  printf '%s' "$out" > "${WORKDIR}/${tag}.json"
  printf '%s' "$out"
}

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

log "sheaf 全旅程开始（workdir=${WORKDIR}）"

# ── 0. 登录自检 ─────────────────────────────────────────────────────────────
log "0/8 登录与账号自检"
as +me > /dev/null 2>&1 || { echo "✗ 未登录：先 as +connect 或 as auth login" >&2; exit 1; }
step "已登录"

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
log "5/8 变体与账号稿"
VARIANT="$(asj variant sheaf variants create --project-id "$PROJECT_ID" --master-version-id "$MASTER_VERSION_ID" \
  --target "wechatoa,${ACCOUNT}" --target-platform wechat_oa --content-kind article)"
VARIANT_ID="$(printf '%s' "$VARIANT" | jget '.id')"
PROFILE_VERSION_ID="$(printf '%s' "$VARIANT" | jget '.accountProfileVersionId')"
cat > "${WORKDIR}/variant.md" <<EOF
# ${TITLE}（公众号稿）

母稿版本 ${MASTER_VERSION_ID} 按账号画像改写后的账号稿：标题更抓人、
段落更短、口语化收尾引导在看/转发。
EOF
VVERSION="$(asj variant-version sheaf variants version --variant-id "$VARIANT_ID" \
  --content-file "${WORKDIR}/variant.md" --title "$TITLE" \
  --master-version-id "$MASTER_VERSION_ID" --profile-version-id "$PROFILE_VERSION_ID" \
  --content-kind article --client-request-id "${RUN}-vv")"
VARIANT_VERSION_ID="$(printf '%s' "$VVERSION" | jget '.id')"
step "variant=${VARIANT_ID} version=${VARIANT_VERSION_ID}（$(printf '%s' "$VVERSION" | jget '.status')）"

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

# ── 7. 投递意图 prepare（固定 payload；输出可重建材料） ──────────────────────
log "7/8 投递意图 prepare"
DELIVERY="$(asj delivery sheaf deliveries prepare --variant-version-id "$VARIANT_VERSION_ID" --operation-kind draft_create)"
DELIVERY_ID="$(printf '%s' "$DELIVERY" | jget '.id')"
IDEMPOTENCY_KEY="$(printf '%s' "$DELIVERY" | jget '.idempotencyKey')"
CONTENT_REF="$(printf '%s' "$DELIVERY" | jget '.renderedContent.contentRef')"
ARTICLE_TITLE="$(printf '%s' "$DELIVERY" | jget '.renderedContent.title')"
# contentRef=变体版本（结构化引用）：正文经版本链取回（本脚本自持 VARIANT_ID；
# 续接场景从 delivery.variantId 列版本后按 id 匹配），包成最小 HTML 供 wechatoa
# 建稿（生产旅程由 Agent 按账号画像渲染）
as --json sheaf variants list --variant-id "$VARIANT_ID" > "${WORKDIR}/variant-versions.json"
node -e "
  const fs=require('fs');
  const d=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));
  const md=((d.items||[]).find(it=>it.id===process.argv[2]) ?? (d.items||[])[0])?.contentMd ?? '';
  const title=process.argv[3];
  const esc=s=>s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  const html='<html><body><h1>'+esc(title)+'</h1>'+
    md.split(/\n{2,}/).map(p=>'<p>'+esc(p).replace(/\n/g,'<br>')+'</p>').join('')+
    '</body></html>';
  fs.writeFileSync(process.argv[4], html);
" "${WORKDIR}/variant-versions.json" "$CONTENT_REF" "$ARTICLE_TITLE" "${WORKDIR}/article.html"
[ -s "${WORKDIR}/article.html" ] || { echo "✗ 正文取回失败（contentRef=${CONTENT_REF}）" >&2; exit 1; }
step "intent=${DELIVERY_ID} idempotencyKey=${IDEMPOTENCY_KEY} contentRef=${CONTENT_REF} assetSetRevision=$(printf '%s' "$DELIVERY" | jget '.assetSetRevision')"

if [ "$SKIP_PUBLISH" = "1" ]; then
  log "完成（--skip-publish：已到 prepare，材料在 ${WORKDIR}）"
  exit 0
fi

# ── 8. wechatoa 建稿 → reconcile 回执核对 ──────────────────────────────────
log "8/8 wechatoa 建稿与回执核对"
# 图片直接用本地原件（与 Files 侧字节同源；重下载需按真实扩展名命名——
# 伪扩展名（.img）会被 wechatoa→Files 的 purpose 策略按扩展名拒绝）
CONTENT_DL_ARGS=()
for img in "${CONTENT_IMAGES[@]}"; do CONTENT_DL_ARGS+=("$(cd "$(dirname "$img")" && pwd)/$(basename "$img")"); done
PUBLISH_ARGS=(wechatoa draft publish --account-id "$ACCOUNT"
  --file "${WORKDIR}/article.html" --title "$ARTICLE_TITLE" --cover "$COVER")
if [ ${#CONTENT_DL_ARGS[@]} -gt 0 ]; then
  PUBLISH_ARGS+=(--content-images "${CONTENT_DL_ARGS[@]}")
fi
PUBLISH_ARGS+=(--intent-id "$DELIVERY_ID" --idempotency-key "$IDEMPOTENCY_KEY")
PUBLISH="$(asj publish "${PUBLISH_ARGS[@]}")"
OPERATION_ID="$(printf '%s' "$PUBLISH" | jget '.operation_id')"
step "media_id=$(printf '%s' "$PUBLISH" | jget '.media_id') operation=${OPERATION_ID}"

RECONCILE="$(asj reconcile sheaf deliveries reconcile --delivery-id "$DELIVERY_ID" --operation-id "$OPERATION_ID")"
FINAL_STATUS="$(printf '%s' "$RECONCILE" | jget '.status')"
step "delivery status=${FINAL_STATUS}"

log "旅程完成：${TITLE}"
printf '  选题 topic=%s\n  项目 project=%s\n  母稿 masterVersion=%s\n  变体版本 variantVersion=%s\n  投递 intent=%s（%s）\n  材料 workdir=%s\n' \
  "$TOPIC_ID" "$PROJECT_ID" "$MASTER_VERSION_ID" "$VARIANT_VERSION_ID" "$DELIVERY_ID" "$FINAL_STATUS" "$WORKDIR" >&2
if [ "$FINAL_STATUS" = "synced" ] || [ "$FINAL_STATUS" = "unknown" ]; then
  exit 0
fi
echo "✗ 投递终态非 synced（${FINAL_STATUS}）——排查：as sheaf deliveries list --variant-version-id ${VARIANT_VERSION_ID}" >&2
exit 1
