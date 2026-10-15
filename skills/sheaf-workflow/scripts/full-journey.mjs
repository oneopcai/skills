#!/usr/bin/env node
/** Node >=22 only. No shell, .cmd execution, external hashing or JSON utilities.
 * Freeze images before the variant; import exact frozen bytes; reconcile is authoritative.
 */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const UUID = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const HASH = /^[0-9a-f]{64}$/i;
const PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
export class WorkflowError extends Error {
  constructor(message, code = 1) { super(message); this.code = code; }
}
export const usage = `用法：node scripts/full-journey.mjs --account <公众号UUID> [选项]
      node scripts/full-journey.mjs --recheck-delivery-id <投递UUID> [--workdir <dir>]
  --account <uuid>       所选公众号；完整旅程先官方预检，不自动切号
  --url <url>            素材链接
  --title <title>        文章标题
  --cover <file>         封面图
  --content-image <file> 正文图，可重复
  --workdir <dir>        保存 JSON / stderr / exit-code 与冻结材料
  --prepare-only        仅冻结材料；未官方探测、未交稿、未核验，非 synced
  --recheck-delivery-id <uuid>
                        仅 reconcile；不上传、不 import/update/publish
  --help / -h           帮助
依赖：Node >=22、CLI >=0.6.38。微信草稿发布属于独立动作。
`;

export function parseArgs(argv) {
  const o = { account: '', url: 'https://example.com/sheaf-demo', title: '', cover: '', images: [], workdir: '', prepareOnly: false, recheck: '' };
  const names = { '--account': 'account', '--url': 'url', '--title': 'title', '--cover': 'cover', '--workdir': 'workdir', '--recheck-delivery-id': 'recheck' };
  for (let i = 0; i < argv.length; i++) {
    const flag = argv[i];
    if (flag === '--help' || flag === '-h') return { help: true };
    if (flag === '--prepare-only') { o.prepareOnly = true; continue; }
    if (!(flag in names) && flag !== '--content-image') throw new WorkflowError(`未知参数：${flag}（--help 查看用法）`, 2);
    const value = argv[++i];
    if (!value || value.startsWith('--')) throw new WorkflowError(`${flag} 缺少值`, 2);
    if (flag === '--content-image') o.images.push(value); else o[names[flag]] = value;
  }
  if (o.prepareOnly && o.recheck) throw new WorkflowError('--prepare-only 与 --recheck-delivery-id 互斥', 2);
  if (!o.recheck && !o.account) throw new WorkflowError('缺少 --account <公众号UUID>', 2);
  for (const [name, value] of [['--account', o.account], ['--recheck-delivery-id', o.recheck]]) {
    if (value && !UUID.test(value)) throw new WorkflowError(`${name} 须为 UUID`, 2);
  }
  return o;
}

/** Validate the package's own bin entry, then run it with this Node, never a launcher shell. */
function packageEntry(root) {
  try {
    const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
    if (pkg.name !== '@oneopcai/agentschool-cli' || typeof pkg.bin?.as !== 'string') return null;
    const entry = path.resolve(root, pkg.bin.as);
    const rel = path.relative(root, entry);
    if (rel.startsWith('..') || path.isAbsolute(rel) || !fs.statSync(entry).isFile()) return null;
    return fs.realpathSync(entry);
  } catch { return null; }
}

export function resolveCliEntry(env = process.env, platform = process.platform) {
  let unknownLauncher = false;
  for (const value of (env.PATH || env.Path || '').split(path.delimiter).filter(Boolean)) {
    const dir = value.replace(/^"|"$/g, '');
    const wrappers = platform === 'win32' ? ['as.cmd', 'as', 'agentschool.cmd', 'agentschool'] : ['as', 'agentschool'];
    for (const name of wrappers) {
      const launcher = path.join(dir, name);
      if (!fs.existsSync(launcher)) continue;
      const real = fs.realpathSync(launcher);
      const roots = [path.join(dir, 'node_modules/@oneopcai/agentschool-cli'), path.join(dir, '../lib/node_modules/@oneopcai/agentschool-cli'), path.join(dir, '../@oneopcai/agentschool-cli')];
      // npm Unix/.bin symlinks point straight at the entry. Locate its enclosing package.
      for (let parent = path.dirname(real), n = 0; n < 5; n++, parent = path.dirname(parent)) {
        const entry = packageEntry(parent);
        if (entry === real) return entry;
      }
      for (const root of roots) { const entry = packageEntry(root); if (entry) return entry; }
      // Unix may also have the GNU assembler named "as"; never execute it.
      unknownLauncher = true;
    }
  }
  if (unknownLauncher) throw new WorkflowError('PATH 中的 as 启动器无法定位官方 CLI JS 入口；请检查 CLI 安装，拒绝退回 Shell/.cmd 执行');
  throw new WorkflowError('未找到已安装的 as：需要 CLI >=0.6.38；请把安装目录加入 PATH');
}

export function cliInvocation(entry, args) { return { executable: process.execPath, args: [entry, ...args], options: { shell: false } }; }
function hash(bytes) { return createHash('sha256').update(bytes).digest('hex'); }
function required(value, label) {
  if (value === null || value === undefined || value === '') throw new WorkflowError(`响应缺少 ${label}`);
  return value;
}
function parseJson(text, tag) {
  try { return JSON.parse(text.replace(/^\uFEFF/, '')); } catch { throw new WorkflowError(`${tag} 返回非 JSON；原始输出已保留`); }
}
export function checkResult(d, expected = '') {
  const v = d.verification;
  if (d.status !== 'synced' || !UUID.test(d.articleId || '') || (expected && d.articleId !== expected)
      || v?.method !== 'wechatoa_article_readback' || !UUID.test(v.attemptId || '')
      || typeof v.checkedAt !== 'string' || !/(Z|[+-]\d{2}:?\d{2})$/.test(v.checkedAt) || !Number.isFinite(Date.parse(v.checkedAt))
      || !Number.isInteger(v.contentVersion) || v.contentVersion < 1) {
    throw new WorkflowError(`完成门未通过：status=${d.status ?? '-'}；须 synced、正确 articleId 与完整 verification`);
  }
  return v;
}

export function runJourney(argv, { stderr = process.stderr, stdout = process.stdout } = {}) {
  const o = parseArgs(argv);
  if (o.help) { stdout.write(usage); return 0; }
  if (Number(process.versions.node.split('.')[0]) < 22) throw new WorkflowError('需要 Node >=22');
  const entry = resolveCliEntry();
  const invoke = (args) => {
    const call = cliInvocation(entry, args);
    return spawnSync(call.executable, call.args, { ...call.options, encoding: 'utf8', timeout: 120000, maxBuffer: 16 * 1024 * 1024, windowsHide: true });
  };
  const ver = invoke(['--version']);
  const m = /^v?(\d+)\.(\d+)\.(\d+)$/.exec((ver.stdout || '').trim());
  if (ver.error || ver.status !== 0 || !m || !(+m[1] > 0 || +m[2] > 6 || (+m[2] === 6 && +m[3] >= 38))) throw new WorkflowError('需要 CLI >=0.6.38；当前安装不可用或版本过低');
  const run = `sheaf-${Date.now()}-${randomUUID().slice(0, 8)}`;
  const workdir = o.workdir ? path.resolve(o.workdir) : fs.mkdtempSync(path.join(os.tmpdir(), `${run}-`));
  fs.mkdirSync(workdir, { recursive: true });
  const log = (s) => stderr.write(`${s}\n`);
  let deliveryId = o.recheck;
  const guidance = () => {
    if (deliveryId) {
      log(`  排查：as sheaf deliveries get ${deliveryId}`);
      log(`  只读重核（零平台写，可记录核验 attempt/审计）：as sheaf deliveries reconcile --delivery-id ${deliveryId} --client-request-id <新生成键>`);
    }
    log(`  原始 JSON / stderr / exit-code 与恢复材料：${workdir}；不重复 import`);
  };
  const asj = (tag, args) => {
    const r = invoke(['--json', ...args]);
    const rc = r.error || r.signal ? (r.status || 1) : (r.status ?? 1);
    fs.writeFileSync(path.join(workdir, `${tag}.json`), r.stdout || '');
    fs.writeFileSync(path.join(workdir, `${tag}.err`), (r.stderr || '') + (r.error ? `\n${r.error.message}\n` : ''));
    fs.writeFileSync(path.join(workdir, `${tag}.exit-code`), `${rc}\n`);
    if (rc !== 0) {
      if (r.stderr) log(r.stderr);
      try {
        const d = JSON.parse(r.stdout);
        log(`✗ status=${d.status ?? '-'} errorCode=${d.errorCode ?? '-'} articleId=${d.articleId ?? '-'}`);
        if (d.errorCode === 'target_account_not_accessible') log('  文章可能已落库；冻结公众号不可访问，整体投递未成功。修复账号后重核同一投递，不重复 import。');
      } catch { /* Keep non-JSON raw stdout, too. */ }
      throw new WorkflowError(`步骤失败：${tag}，exit=${rc}；产物 ${path.join(workdir, tag)}.*`);
    }
    return parseJson(r.stdout, tag);
  };
  const showVerification = (v) => log(`verification：method=${v.method} attemptId=${v.attemptId} checkedAt=${v.checkedAt} contentVersion=${v.contentVersion}`);
  try {
    if (o.recheck) {
      const key = randomUUID();
      const d = asj('recheck', ['sheaf', 'deliveries', 'reconcile', '--delivery-id', deliveryId, '--client-request-id', key]);
      showVerification(checkResult(d));
      log(`clientRequestId=${key}`);
      log('只读重核返回 synced（以上为返回摘要的核验时点；官方证据吸收保留旧 attempt，历史补核可产生新 attempt，请与重核前摘要比较）');
      return 0;
    }
    const title = o.title || `sheaf 旅程 ${new Date().toISOString()}`;
    const cover = o.cover ? path.resolve(o.cover) : path.join(workdir, 'cover.png');
    if (!o.cover) fs.writeFileSync(cover, Buffer.from(PNG, 'base64'));
    const images = o.images.length ? o.images.map(p => path.resolve(p)) : [path.join(workdir, 'content-1.png')];
    if (!o.images.length) fs.writeFileSync(images[0], Buffer.from(PNG, 'base64'));
    const paths = new Map();
    for (const file of [cover, ...images]) {
      if (!fs.existsSync(file) || !fs.statSync(file).isFile()) throw new WorkflowError(`图片文件不存在或非普通文件：${file}`);
      const name = path.basename(file);
      if (/[\x00-\x1f\x7f>?#\\`,]/.test(name)) throw new WorkflowError(`图片文件名含不支持的路径/回执分隔符：${name}`);
      const digest = hash(fs.readFileSync(file));
      if (paths.has(name) && paths.get(name) !== digest) throw new WorkflowError(`同路径不同字节：assets/${name}，拒绝交稿`);
      paths.set(name, digest);
    }
    log(`== sheaf 全旅程开始（workdir=${workdir}） ==`);
    log('0/8 登录与账号自检');
    const identity = invoke(['+me']);
    if (identity.error || identity.status !== 0) throw new WorkflowError('身份核验失败：先 as +connect；也可能是网络或服务暂不可用');
    if (!o.prepareOnly) {
      const account = asj('account-verify', ['wechatoa', 'accounts', 'verify', o.account]);
      if (account.ok !== true) throw new WorkflowError(`目标公众号未通过官方连通性预检：reason=${account.reason ?? 'unavailable'} errcode=${account.errcode ?? '-'}；尚未创建内容、上传或交稿；占位号不可用，不自动切号`);
      log('目标公众号官方预检通过（最终 reconcile 仍按冻结账号再次核验）');
    }
    log('1/8 收藏素材');
    const capture = asj('capture', ['sheaf', 'captures', 'add', '--url', o.url, '--client-request-id', `${run}-cap`]);
    const source = required(capture.capture?.sourceId, 'capture.sourceId');
    log('2/8 选题与评估');
    const topic = required(asj('topic', ['sheaf', 'topics', 'create', '--title', title, '--source-ids', source]).id, 'topic.id');
    asj('assess', ['sheaf', 'topics', 'assess', topic, '--rule-version', 'v1', '--score', '85']);
    log('3/8 创建项目');
    const project = required(asj('project', ['sheaf', 'projects', 'create', '--topic-id', topic, '--title', title]).id, 'project.id');
    log('4/8 母稿编辑与确认');
    const masterFile = path.join(workdir, 'master.md');
    fs.writeFileSync(masterFile, `# ${title}\n\n素材链接：${o.url}\n\n## 正文\n\n这是经 sheaf 工作流生成的母稿正文。确认后固化为不可变版本，\n变体在此基础上按账号画像改写。\n`);
    const draft = asj('master-edit', ['sheaf', 'master', 'edit', '--project-id', project, '--title', title, '--content-file', masterFile, '--if-match', '0']);
    const master = required(asj('master-confirm', ['sheaf', 'master', 'confirm', '--project-id', project, '--if-match', String(required(draft.draftVersion, 'draftVersion')), '--idempotency-key', `${run}-mc`]).id, 'master.id');
    log('5/8 变体与账号稿');
    const variant = asj('variant', ['sheaf', 'variants', 'create', '--project-id', project, '--master-version-id', master, '--target', `wechatoa,${o.account}`, '--target-platform', 'wechat_oa', '--content-kind', 'article']);
    const variantId = required(variant.id, 'variant.id');
    const variantFile = path.join(workdir, 'variant.md');
    const refs = images.map(p => { const ref = `assets/${path.basename(p)}`; return /[\s()]/.test(ref) ? `![配图](<${ref}>)` : `![配图](${ref})`; });
    fs.writeFileSync(variantFile, `# ${title}\n\n母稿版本 ${master} 按账号画像改写后的账号稿：标题更抓人、段落更短、口语化收尾引导在看/转发。\n${refs.map(x => `\n${x}\n`).join('')}`);
    const version = required(asj('variant-version', ['sheaf', 'variants', 'version', '--variant-id', variantId, '--content-file', variantFile, '--title', title, '--master-version-id', master, '--profile-version-id', required(variant.accountProfileVersionId, 'accountProfileVersionId'), '--content-kind', 'article', '--client-request-id', `${run}-vv`]).id, 'variantVersion.id');
    log('6/8 资产集合');
    const coverId = required(asj('upload-cover', ['files', 'upload', cover, '--purpose', 'general.image']).file_id, 'cover.file_id');
    const contentIds = images.map((p, i) => required(asj(`upload-content-${i + 1}`, ['files', 'upload', p, '--purpose', 'general.image']).file_id, 'image.file_id'));
    const aset = asj('assets-set', ['sheaf', 'assets', 'set', '--variant-id', variantId, '--variant-version-id', version]);
    asj('assets-reorder', ['sheaf', 'assets', 'reorder', '--variant-id', variantId, '--asset-set-id', required(aset.id, 'assetSet.id'), '--base-revision', String(required(aset.revision, 'revision')), ...[coverId, ...contentIds].flatMap((id, i) => ['--item', `${i === 0 ? 'cover' : 'content'},file=${id},purpose=general.image`])]);
    log('7/8 投递意图 prepare');
    const delivery = asj('delivery', ['sheaf', 'deliveries', 'prepare', '--variant-version-id', version]);
    deliveryId = required(delivery.id, 'delivery.id');
    const contentRef = required(delivery.renderedContent?.contentRef, 'contentRef');
    const articleTitle = required(delivery.renderedContent?.title, 'frozen title');
    const versions = asj('variant-versions', ['sheaf', 'variants', 'list', '--variant-id', variantId]);
    const rows = Array.isArray(versions) ? versions : versions.items;
    const frozen = rows?.find(v => v.id === contentRef);
    if (!frozen || !frozen.contentMd || !HASH.test(frozen.contentSha256 || '')) throw new WorkflowError('精确版本未命中或正文/哈希缺失；不兜底取首个');
    const bytes = Buffer.from(frozen.contentMd, 'utf8');
    fs.writeFileSync(path.join(workdir, 'article.md'), bytes);
    fs.writeFileSync(path.join(workdir, 'content.sha256'), frozen.contentSha256);
    if (hash(bytes) !== frozen.contentSha256) throw new WorkflowError('正文完整性校验失败；冻结 SHA 与原始字节不符，零平台写退出');
    if (o.prepareOnly) { log('完成（--prepare-only：已冻结材料；未交稿、未 reconcile，本终点不是 synced）'); return 0; }
    log('8/8 wechatoa 文章域交稿与回执核对');
    const articleRoot = path.join(workdir, 'article-root');
    fs.mkdirSync(path.join(articleRoot, 'assets'), { recursive: true });
    fs.writeFileSync(path.join(articleRoot, 'article.md'), bytes);
    const frozenHashes = new Map();
    for (const a of delivery.payloadAssets || []) {
      if (frozenHashes.has(a.fileId) && frozenHashes.get(a.fileId) !== a.fileSha256) throw new WorkflowError('冻结资产同 fileId 冲突，拒绝交稿');
      frozenHashes.set(a.fileId, a.fileSha256);
    }
    const slots = [cover, ...images].map((file, i) => {
      const id = [coverId, ...contentIds][i], sha = hash(fs.readFileSync(file));
      if (!frozenHashes.has(id) || (frozenHashes.get(id) && frozenHashes.get(id) !== sha)) throw new WorkflowError('源哈希不符或冻结资产缺失；零平台写退出');
      fs.copyFileSync(file, path.join(articleRoot, 'assets', path.basename(file)));
      return { slot: i === 0 ? 'cover' : 'content', logicalPath: `assets/${path.basename(file)}`, sha };
    });
    const imported = asj('import', ['wechatoa', 'article', 'import', path.join(articleRoot, 'article.md'), '--assets', articleRoot, '--cover', path.join(articleRoot, 'assets', path.basename(cover)), '--cover-logical-path', `assets/${path.basename(cover)}`, '--account-id', o.account]);
    const article = required(imported.articleId, 'import.articleId');
    if (/^\s|\s$/.test(articleTitle)) asj('title-align', ['wechatoa', 'article', 'update', article, '--title', articleTitle]);
    const byPath = new Map((imported.assets || []).map(a => [a.logicalPath, a.assetId]));
    const evidence = slots.map(s => {
      const asset = required(s.slot === 'cover' ? imported.coverAssetId : byPath.get(s.logicalPath), `import asset ${s.logicalPath}`);
      return `slot=${s.slot},logical-path=${s.logicalPath},asset-id=${asset},sha256=${s.sha}`;
    });
    fs.writeFileSync(path.join(workdir, 'evidence-assets.txt'), evidence.join('\n') + '\n');
    const reconciled = asj('reconcile', ['sheaf', 'deliveries', 'reconcile', '--delivery-id', deliveryId, '--article-id', article, '--title', articleTitle, '--markdown-sha256', frozen.contentSha256, ...evidence.flatMap(e => ['--asset', e])]);
    showVerification(checkResult(reconciled, article));
    log(`旅程完成：synced，articleId=${article} deliveryId=${deliveryId} workdir=${workdir}`);
    return 0;
  } catch (error) {
    log(`✗ ${error.message}`);
    guidance();
    return error instanceof WorkflowError ? error.code : 1;
  }
}

if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  try { process.exitCode = runJourney(process.argv.slice(2)); }
  catch (error) { console.error(`✗ ${error.message}`); process.exitCode = error instanceof WorkflowError ? error.code : 1; }
}
