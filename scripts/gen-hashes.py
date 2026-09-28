#!/usr/bin/env python3
"""重新生成 skills.json 的每文件 sha256 清单（改 skill 内容后运行）。

CLI 侧（as skills install >= 0.5.8）拉取后按此清单校验完整性——
对标 npm integrity hash：防传输损坏与基本篡改；清单缺失时 CLI 宽松兼容。
日常发布用 scripts/publish.sh（本脚本被其自动调用）。
"""
import hashlib
import json
import os

MANIFEST = os.path.join(os.path.dirname(__file__), "..", "skills.json")
CRLF = b"\r\n"
LF = b"\n"


def main():
    with open(MANIFEST, encoding="utf-8") as f:
        manifest = json.load(f)
    for entry in manifest["skills"]:
        base = os.path.join(os.path.dirname(MANIFEST), entry["path"])
        hashes = {}
        for root, _, files in os.walk(base):
            for name in files:
                p = os.path.join(root, name)
                rel = os.path.relpath(p, base).replace("\\", "/")
                # LF 规范化 = 远端 git raw 的字节形态（Windows 工作区 CRLF 无关）
                raw = open(p, "rb").read().replace(CRLF, LF)
                hashes[rel] = hashlib.sha256(raw).hexdigest()
        entry["sha256"] = dict(sorted(hashes.items()))
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print(f"regenerated sha256 for {len(manifest['skills'])} skill(s)")


if __name__ == "__main__":
    main()
