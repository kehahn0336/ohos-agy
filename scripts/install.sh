#!/bin/sh
# ohos-agy 一键安装（HarmonyOS PC / aarch64）
# 用法: bash scripts/install.sh [--force]
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
OPT="$HOME/opt"
AGY_DIR="$OPT/agy"
BIN_DIR="$OPT/bin"
FORCE=${1:-}

PY=$(command -v python3 2>/dev/null || true)
[ -n "$PY" ] || PY=/data/storage/el1/bundle/libs/arm64/python/bin/python3
SIGN=/data/service/hnp/bin/binary-sign-tool
# 鸿蒙上 PATH 里可能有 rm 的 shim（#!/bin/bash，鸿蒙没有 /bin/bash），优先用 toybox 的
RM=/usr/bin/rm
[ -x "$RM" ] || RM=rm
BASE="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app"
PLATFORM="linux_arm64_musl"

say() { printf '\033[1m==> %s\033[0m\n' "$1"; }

[ -x "$SIGN" ] || { echo "缺少 $SIGN（鸿蒙 PC 自带），无法签名" >&2; exit 1; }
[ -x "$PY" ]   || { echo "缺少 python3" >&2; exit 1; }

if [ -x "$AGY_DIR/agy" ] && [ "$FORCE" != "--force" ]; then
  say "已存在 $AGY_DIR/agy（$("$AGY_DIR/agy" --version 2>/dev/null || echo '?')）"
  echo "要覆盖重装请加 --force"
else
  say "1/6 查询最新版本"
  TMP=$(mktemp -d 2>/dev/null || echo "$HOME/.cache/agy-install")
  mkdir -p "$TMP"
  curl -fsSL "$BASE/manifests/$PLATFORM.json" -o "$TMP/manifest.json"
  VERSION=$("$PY" -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$TMP/manifest.json")
  URL=$("$PY" -c 'import json,sys;print(json.load(open(sys.argv[1]))["url"])' "$TMP/manifest.json")
  SHA=$("$PY" -c 'import json,sys;print(json.load(open(sys.argv[1]))["sha512"])' "$TMP/manifest.json")
  echo "    version=$VERSION"

  say "2/6 下载并校验"
  curl -fL --retry 3 -o "$TMP/agy.tar.gz" "$URL"
  ACTUAL=$("$PY" - "$TMP/agy.tar.gz" <<'PYEOF'
import hashlib,sys
h=hashlib.sha512()
with open(sys.argv[1],'rb') as f:
    for chunk in iter(lambda: f.read(1<<20), b''):
        h.update(chunk)
print(h.hexdigest())
PYEOF
)
  [ "$ACTUAL" = "$SHA" ] || { echo "校验失败，放弃安装" >&2; exit 1; }
  tar -xzf "$TMP/agy.tar.gz" -C "$TMP" antigravity

  say "3/6 打内核版本补丁"
  "$PY" "$HERE/repatch.py" "$TMP/antigravity" "$TMP/agy.patched"

  say "4/6 自签名"
  "$SIGN" sign -inFile "$TMP/agy.patched" -outFile "$TMP/agy.signed" -selfSign "1" >/dev/null
  mkdir -p "$AGY_DIR"
  cp "$TMP/agy.signed" "$AGY_DIR/agy.new"
  chmod +x "$AGY_DIR/agy.new"
  mv "$AGY_DIR/agy.new" "$AGY_DIR/agy"
  "$RM" -rf "$TMP"
fi

say "5/6 准备自签名 bash"
mkdir -p "$BIN_DIR"
BASH_SRC=""
for c in /data/service/hnp/bin/bash "$HOME/.harmonybrew/bin/bash" /bin/bash /usr/bin/bash; do
  [ -x "$c" ] && BASH_SRC=$c && break
done
if [ -z "$BASH_SRC" ]; then
  echo "找不到可用的 bash，请先安装（brew install bash）" >&2
else
  # 已经是签名过、且能跑的就不重复处理
  if [ -x "$BIN_DIR/bash" ] && "$BIN_DIR/bash" -c 'exit 0' 2>/dev/null; then
    echo "    $BIN_DIR/bash 已就绪"
  else
    cp "$BASH_SRC" "$BIN_DIR/bash.raw"
    "$SIGN" sign -inFile "$BIN_DIR/bash.raw" -outFile "$BIN_DIR/bash" -selfSign "1" >/dev/null
    chmod +x "$BIN_DIR/bash"
    "$RM" -f "$BIN_DIR/bash.raw"
    "$BIN_DIR/bash" -c 'exit 0' || { echo "自签名 bash 无法执行，PATH 修复会失败" >&2; }
    echo "    $BIN_DIR/bash <- $BASH_SRC"
  fi
fi

say "6/6 安装启动器"
cp "$ROOT/templates/agy.launcher.sh" "$BIN_DIR/agy"
chmod +x "$BIN_DIR/agy"

MARK="# >>> ohos-agy >>>"
if [ -f "$HOME/.zshrc" ] && ! grep -q 'opt/bin' "$HOME/.zshrc" 2>/dev/null; then
  {
    echo ""
    echo "$MARK"
    echo 'export PATH="$HOME/opt/bin:$PATH"'
    echo "# <<< ohos-agy <<<"
  } >> "$HOME/.zshrc"
  echo "    已写入 ~/.zshrc"
elif [ ! -f "$HOME/.zshrc" ]; then
  echo "    未发现 ~/.zshrc，跳过 PATH 写入；请手动把 $HOME/opt/bin 加入 PATH"
else
  echo "    ~/.zshrc 已有 opt/bin，跳过"
fi

say "完成：$("$AGY_DIR/agy" --version 2>/dev/null || echo '版本读取失败')"
echo "新开终端或执行 'exec zsh'，然后直接敲 agy"
echo "冒烟测试：agy -p \"运行 echo ok 并告诉我输出\""
