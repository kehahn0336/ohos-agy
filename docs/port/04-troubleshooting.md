# 04 · 故障对照表

## 按症状查

| 症状 | 退出码 | 原因 | 处理 |
|---|---|---|---|
| `FATAL: kernel too old` | 134 | 补丁没打上 / 被自动更新覆盖 | 重跑 `scripts/repatch.py` 再签名 |
| 突然 `Permission denied`（126），版本号还变了 | 126 | **agy 后台自更新**把二进制换成了官方未签名版 | `bash scripts/install.sh --force` 重装；确认启动器带 `AGY_CLI_DISABLE_AUTO_UPDATE=1` |
| `zsh: invalid system call (core dumped)` | 159 | 进了命名空间沙箱 | 用启动器（内含 `--dangerously-skip-permissions`） |
| `run bash: fork/exec .../bundle/.../bash: permission denied` | 0（工具内失败） | PATH 里的 bash 在 HAP bundle 里 | 自签名 bash 放 `~/opt/bin` 并前置 PATH |
| `Permission denied` 直接执行任何 ELF | 126 | 该 ELF 没签名 | `binary-sign-tool sign -selfSign 1` |
| `timeout: exec ...: Operation not permitted` | 126 | 二进制放在 `/tmp` 下 | 移到 `$HOME/**` 再执行 |
| `exec format error` | 126 | 架构不对（下了 x86 版） | 用 `linux_arm64_musl` manifest |
| `Eligibility check failed ... EOF` | 1 | 网络到 `*.googleapis.com` 抖动 | 直接重试，与移植无关 |
| 命令“执行了”但无输出 | 0 | headless 下工具被软拒绝 | 确认带了 `--dangerously-skip-permissions` |
| `No auth type is selected` / `Please sign in` | 1 | 未登录 | 跑一次 `agy`（不加参数），浏览器授权后把 code 粘回终端 |

## 升级 agy 之后

自动更新会覆盖补丁并破坏签名。稳妥做法：

```sh
# 1. 关掉自动更新（可选，改 settings）
#    ~/.gemini/antigravity-cli/settings.json

# 2. 重新下载 + 打补丁 + 签名
bash scripts/install.sh

# 3. 验证
agy --version && agy -p "运行 echo ok"
```

## 排查手法

**要看工具的真实报错**，别只看模型转述：

```sh
agy -p "..." --output-format stream-json | grep -o '"output":"[^"]*"'
```

**要看 agy 自己的日志**：

```sh
ls -t ~/.gemini/antigravity-cli/log/*.log | head -1
```

**要确认某个系统调用是否被拦**：

```sh
python3 scripts/probe_seccomp.py
```

**要确认补丁是否在**：

```sh
# 用 llvm-objdump 看那两条分支是否已变 NOP
~/.harmonybrew/opt/llvm@22/bin/llvm-objdump -d --start-address=0xafc0b78 \
  --stop-address=0xafc0b84 ~/opt/agy/agy | tail -4
# 期望看到  d503201f  nop
```

## 已知环境事实（供以后排查参考）

- `uname -a` → `HarmonyOS localhost HongMeng Kernel 1.13.0 ... aarch64 Toybox`
- libc 是 **musl**（`/lib/ld-musl-aarch64.so.1`），没有 glibc
- `/bin/sh` 是 Toybox 的 sh，可用；`/bin/bash` 不存在
- `ptrace` 被禁（`PTRACE_TRACEME` → EACCES），不能用 strace/gdb
- `hilog` 在应用沙箱里读不到内容（输出 0 行）
- 用户区 `$HOME` 是 hmdfs：**不支持 symlink**（npm 需 `--no-bin-links`）
