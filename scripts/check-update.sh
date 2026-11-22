#!/bin/sh
# SPDX-License-Identifier: MIT
# 检查 agy 是否有新版本（只查询 manifest，不下载、不改动任何文件）
set -u

PY=$(command -v python3 2>/dev/null || true)
[ -n "$PY" ] || PY=/data/storage/el1/bundle/libs/arm64/python/bin/python3
AGY="$HOME/opt/agy/agy"
BASE="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app"
PLATFORM="linux_arm64_musl"

[ -x "$AGY" ] || { echo "未安装：$AGY（先跑 scripts/install.sh）" >&2; exit 1; }

LOCAL=$("$AGY" --version 2>/dev/null | tail -1)
MANIFEST=$(curl -fsSL --max-time 20 "$BASE/manifests/$PLATFORM.json" 2>/dev/null) || {
  echo "查询失败：连不上发布端点（网络问题，或端点变更）" >&2
  exit 2
}

LATEST=$(printf '%s' "$MANIFEST" | "$PY" -c 'import json,sys;print(json.load(sys.stdin)["version"])' 2>/dev/null) || {
  echo "查询失败：manifest 解析异常" >&2
  exit 2
}

echo "本地版本: $LOCAL"
echo "最新版本: $LATEST"

"$PY" - "$LOCAL" "$LATEST" <<'PYEOF'
import sys

def key(v):
    out = []
    for part in v.split("."):
        num = "".join(ch for ch in part if ch.isdigit())
        out.append(int(num) if num else 0)
    return tuple(out)

local, latest = sys.argv[1], sys.argv[2]
if key(latest) > key(local):
    print("\n→ 有新版本。升级（会重新打补丁并签名）：")
    print("  bash scripts/install.sh --force")
    sys.exit(10)
print("\n→ 已是最新。")
PYEOF
