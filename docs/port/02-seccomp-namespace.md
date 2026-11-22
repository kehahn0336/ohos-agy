# 02 · 执行命令为什么 SIGSYS（命名空间被内核拒绝）

## 现象

TUI 里让它执行任何命令：

```
> 读取这个项目
○ Running (ls -la && find . ...)
zsh: invalid system call (core dumped)  ~/opt/bin/agy
```

headless 下更清楚：

```
$ agy -p "执行 shell 命令 echo hello"
$ echo $?      # 159
```

159 = 128 + 31 = **SIGSYS**。

## 先分清三件事

| 层 | 报错形态 | 程序能否挽救 |
|---|---|---|
| 文件权限 / uid | `EACCES` | 能，捕获后降级 |
| 特权 / capability | `EPERM` | 能，捕获后降级 |
| **seccomp 白名单** | **SIGSYS，进程当场死** | **不能，代码根本没机会跑** |

agy 碰到的是第三种。

## 实测：哪些调用会被杀

`scripts/probe_seccomp.py` 用 fork 逐号探测（不 exec，秒级完成）：

```sh
python3 scripts/probe_seccomp.py
# BLOCKED: [18, 39, 40, 41, 42, 51, 58, 89, 97, 100, 104, ... 460]
```

几个关键的：

| 调用号 | 名称 | 结果 |
|---|---|---|
| 97 | `unshare` | 杀 |
| 268 | `setns` | 杀 |
| 40 | `mount` | 杀 |
| 41 | `pivot_root` | 杀 |
| 51 | `chroot` | 杀 |
| 89 | `readlinkat` | 杀 |
| 435 | `clone3` | 杀 |
| 436 | `close_range` | 杀 |
| 437 | `openat2` | 杀 |
| 444~446 | `landlock_*` | 杀 |
| 317 / 321 | `seccomp` / `bpf` | 杀 |
| 400+ | 绝大多数新调用 | 杀 |

## 真正的凶手：带命名空间标志的 clone

`clone` 本身**没有被禁**，但带 `CLONE_NEW*` 就死。实测：

```
clone(CLONE_VM|CLONE_VFORK)         → 正常（子进程能跑）
clone(CLONE_NEWNS)                  → SIGSYS
clone(CLONE_NEWUSER)                → SIGSYS
clone(CLONE_NEWPID / NEWNET /
      NEWIPC / NEWUTS / NEWCGROUP)  → SIGSYS
```

agy 执行命令前要创建隔离环境（namespace + landlock 那套），第一步 `clone(CLONE_NEW*)` 就被杀。

## 为什么“改返回值”这招不灵

标准 Linux 上，这类能力缺失会返回 `EPERM`，CLI 会走“沙箱不可用，直接执行”的降级分支。鸿蒙直接发信号，**降级逻辑永远轮不到执行**。

我试过把它们全部改成返回 `ENOSYS`（`mov x0, #-38` + `nop` 替换 `bl`）：

- 单独改 landlock(444) → 照崩
- 改 clone3 / close_range / openat2 → 照崩
- 改 unshare / mount / chroot / setns → 照崩
- 改 readlinkat / seccomp / bpf / 全部 prctl 选项 → 照崩
- **把 226 个被禁调用、2149 个调用点一次性全改** → **还是崩**

原因：这一版的 `clone` 是 Go 运行时用内联汇编发的（`MOVD trap+0(FP), R8; SVC`），trap 号和 flags 都在运行时决定，静态扫描找不到可改的字面量。`ptrace` 也被禁（`TRACEME → EACCES`），没法 strace。

## 实际解法：让 agy 不建沙箱

`--dangerously-skip-permissions` 会让 agy 跳过沙箱直接执行（等价于 UI 里的 Turbo 模式）。加上之后不再 SIGSYS。

代价：所有工具调用免确认，文件系统无隔离。

### 试过但无效的开关

| 方式 | 结果 |
|---|---|
| `settings.json` 里 `enableTerminalSandbox: false` | 无效 |
| `settings.json` 里 `permission_mode: "turbo"` | 无效 |
| `--mode accept-edits` | headless 下命令被“自动拒绝”，提示要配 allow 规则或加 flag |
| `--mode auto` | 该账号不可用 |
| `--no-sandbox` | 不是合法参数 |

## 结论

鸿蒙把“创建命名空间”这个能力从第三方应用进程树里彻底拿掉了，而且剥夺方式是**杀死进程**而不是返回错误。这不是权限问题，是内核策略问题——改 `process.platform` 之类的运行时伪装对它无效（这也解释了为什么 dsh 那种 Node 系移植经验在这里用不上：纯 JS 程序不需要内核特性）。
