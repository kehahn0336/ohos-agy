#!/bin/sh
# agy 启动器（由 install.sh 安装到 ~/opt/bin/agy）
#
# 三点缺一不可：
# 1) ~/opt/bin 前置到 PATH —— agy 用 LookPath("bash")，鸿蒙 bundle 里的 bash
#    对第三方 ELF 是 exec 拒绝的，必须命中这里自签名的 bash
# 2) --dangerously-skip-permissions —— 不加会进命名空间沙箱，鸿蒙对
#    clone(CLONE_NEW*) 直接 SIGSYS 杀进程
# 3) 二进制本身已 patch 掉 glibc 的 "kernel too old" 检查并自签名
PATH="$HOME/opt/bin:$PATH"
export PATH
exec "$HOME/opt/agy/agy" --dangerously-skip-permissions "$@"
