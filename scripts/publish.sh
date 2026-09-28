#!/usr/bin/env bash
# 一键发布 skill：重算完整性清单 → 提交 → 双推（gitee + github）。
# 用法：改完 skill 内容后直接 bash scripts/publish.sh "发布说明"
# （不要手动 git commit——本脚本保证清单与内容永远同步提交）
set -euo pipefail
cd "$(dirname "$0")/.."

MSG="${1:-publish: agentschool-skill 更新}"

python scripts/gen-hashes.py

if git diff --quiet -- skills.json; then
  echo "清单无变化（内容未变或 hash 已是最新），无 hash 相关提交需要"
else
  git add skills.json
fi

git add -A
git commit -m "${MSG}"

# 发布前最后防线：清单与文件必须一致
python scripts/verify-hashes.py

git push gitee main
git push github main
echo ""
echo "✓ 已双推。GitHub Actions 将运行 verify-hashes（远端状态可见）"
