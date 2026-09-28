#!/usr/bin/env python3
"""校验 skills.json 的 sha256 清单与文件实际内容一致（CI / pre-push 共用）。

退出码：0=一致；1=不一致或缺失（附修复指引）。
hash 计算与 gen-hashes.py 同款：LF 规范化（与远端 git raw 字节形态一致）。
"""
import hashlib
import json
import os
import sys

MANIFEST = os.path.join(os.path.dirname(__file__), "..", "skills.json")


def main() -> int:
    with open(MANIFEST, encoding="utf-8") as f:
        manifest = json.load(f)
    repo = os.path.dirname(MANIFEST)
    problems = []
    checked = 0
    for entry in manifest["skills"]:
        base = os.path.join(repo, entry["path"])
        hashes = entry.get("sha256") or {}
        if not hashes:
            problems.append(f"{entry['name']}: 清单未提供 sha256（跑 scripts/gen-hashes.py）")
            continue
        for rel, expected in hashes.items():
            p = os.path.join(base, rel)
            if not os.path.isfile(p):
                problems.append(f"{entry['name']}: 清单文件缺失 {rel}")
                continue
            actual = hashlib.sha256(open(p, "rb").read().replace(b"\r\n", b"\n")).hexdigest()
            checked += 1
            if actual != expected:
                problems.append(f"{entry['name']}: hash 不匹配 {rel}")
    if problems:
        print("skills.json 完整性清单与文件不一致：", file=sys.stderr)
        for line in problems:
            print(f"  - {line}", file=sys.stderr)
        print("修复：python scripts/gen-hashes.py && git add skills.json && git commit --amend --no-edit", file=sys.stderr)
        return 1
    print(f"OK: {checked} 个文件 hash 全部一致")
    return 0


if __name__ == "__main__":
    sys.exit(main())
