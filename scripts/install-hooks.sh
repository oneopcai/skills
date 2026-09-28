#!/usr/bin/env bash
# 安装本地 pre-push 钩子：push 前校验 skills.json 完整性清单与文件一致，
# 不一致直接拦截（防"忘跑 gen-hashes 导致所有安装被校验器挡死"的自伤）。
# 新 clone 后跑一次：bash scripts/install-hooks.sh
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p .githooks
cat > .githooks/pre-push <<'HOOK'
#!/usr/bin/env bash
# pre-push: skills.json 完整性清单必须与文件一致
python scripts/verify-hashes.py || {
  echo ""
  echo "✗ push 被拦截：先跑 python scripts/gen-hashes.py 并把 skills.json 纳入本次提交"
  exit 1
}
HOOK
chmod +x .githooks/pre-push
git config core.hooksPath .githooks
echo "✓ pre-push 钩子已安装（core.hooksPath=.githooks，随仓走，clone 内执行本脚本激活）"
