#!/bin/sh
# SPDX-License-Identifier: MIT
# 安装后自检：不联网、不花钱，只查本地状态
set -u

AGY="$HOME/opt/agy/agy"
LAUNCHER="$HOME/opt/bin/agy"
BASH="$HOME/opt/bin/bash"
PY=$(command -v python3 2>/dev/null || echo /data/storage/el1/bundle/libs/arm64/python/bin/python3)
fail=0

ok()   { printf '  \033[32mOK\033[0m   %s\n' "$1"; }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }
warn() { printf '  \033[33mWARN\033[0m %s\n' "$1"; }

echo "[1] 二进制"
[ -x "$AGY" ] && ok "$AGY 存在" || bad "$AGY 不存在，先跑 scripts/install.sh"

VER=$("$AGY" --version 2>&1 | tail -1)
case "$VER" in
  [0-9]*) ok "版本 $VER" ;;
  *) bad "版本读取失败：$VER（很可能是补丁没打，见 docs/01）" ;;
esac

echo "[2] 启动器"
[ -x "$LAUNCHER" ] && ok "启动器存在" || bad "缺 $LAUNCHER"
if grep -q -- "--dangerously-skip-permissions" "$LAUNCHER" 2>/dev/null; then
  ok "已带 --dangerously-skip-permissions"
else
  warn "启动器没带该参数，执行命令会 SIGSYS"
fi
if grep -q "AGY_CLI_DISABLE_AUTO_UPDATE" "$LAUNCHER" 2>/dev/null; then
  ok "已禁用自动更新"
else
  warn "未禁用自动更新：agy 后台更新会换成未签名二进制，下次启动即 Permission denied"
fi

echo "[3] bash"
if [ -x "$BASH" ] && "$BASH" -c 'exit 0' 2>/dev/null; then
  ok "$BASH 可执行（自签名有效）"
else
  bad "$BASH 不可用（未签名 / 缺失），见 docs/03"
fi
HIT=$(PATH="$HOME/opt/bin:$PATH" command -v bash 2>/dev/null)
case "$HIT" in
  "$HOME/opt/bin/bash") ok "PATH 里 bash 指向用户区" ;;
  *) bad "PATH 里 bash 指向 $HIT，agy 会 exec 失败" ;;
esac

echo "[4] 内核补丁标记"
OBJDUMP=$(command -v llvm-objdump 2>/dev/null || true)
[ -n "$OBJDUMP" ] || OBJDUMP="$HOME/.harmonybrew/opt/llvm@22/bin/llvm-objdump"
if [ "$VER" != "1.5.13" ]; then
  warn "版本 $VER 与内置偏移（1.5.13）不同，跳过固定地址检查；判据是第 1 项能正常打印版本"
elif [ -x "$OBJDUMP" ]; then
  NOP=$("$OBJDUMP" -d --start-address=0xafc0b7c --stop-address=0xafc0b80 "$AGY" 2>/dev/null | grep -c "d503201f")
  [ "$NOP" -ge 1 ] && ok "0xafc0b7c 已是 nop（1.5.13 偏移）" \
                   || bad "该地址不是 nop —— 补丁丢了，重跑 repatch.py"
else
  warn "没有 llvm-objdump，跳过"
fi

echo "[5] 登录态"
if [ -f "$HOME/.gemini/antigravity-cli/antigravity-oauth-token" ]; then
  ok "存在 OAuth token"
else
  warn "未登录，跑一次 agy（不加参数）走浏览器授权"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "全部通过。冒烟测试： agy -p \"运行 echo ok 并告诉我输出\""
else
  echo "有 $fail 项失败，按提示处理（docs/04 有对照表）"
fi
exit "$fail"
