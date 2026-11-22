# ohos-agy

在 **HarmonyOS / OpenHarmony PC** 上运行 **Google Antigravity CLI（`agy`）** 的非官方移植工程。

> **状态：可用。** 2026-11-22 实测（HarmonyOS PC / aarch64 / HongMeng Kernel 1.13.0 / agy **1.5.14**；1.5.13 亦验证过）：
> 对话、读写文件、执行 shell、全量构建 HAP 全部通过。

```sh
cd ~/project/ohos-agy
bash scripts/install.sh
exec zsh
agy --version      # 1.5.14
```

---

## 这是什么，不是什么

**是**：一份**二进制补丁 + 运行环境修复**配方。官方 `agy` 只发 macOS / Windows / Linux / Googlebook，安装脚本 `uname -s` 认不出 `HarmonyOS` 就直接退出；但二进制本身能跑，卡点有三处，全部可绕过。

**不是**：不是重实现，也不是把 Antigravity App / IDE 搬到鸿蒙。桌面端那套（Electron 壳 + 203 MB 动态链接 glibc 的 `language_server`）确实搬不动，见 [可行性报告](docs/antigravity-harmonyos-feasibility.md) —— 那份结论仍然成立，只是**不适用于 CLI**。

> 修正说明：早期「本机跑 agy 不可行」的结论，基于 **glibc 动态构建** 且未打内核版本补丁的实验。CLI 的 `linux-arm64-musl` 构建是**静态**链接，补掉 glibc 的启动检查后可以正常运行。

---

## 三个阻塞点

| # | 阻塞点 | 现象 | 解法 |
|---|---|---|---|
| 1 | glibc 内核版本检查 | `FATAL: kernel too old`，退出码 134（SIGABRT） | NOP 掉两处条件分支 → [01](docs/port/01-kernel-too-old.md) |
| 2 | 终端沙箱用命名空间 | 执行命令瞬间 SIGSYS（rc=159），进程被杀 | `--dangerously-skip-permissions` 跳过沙箱 → [02](docs/port/02-seccomp-namespace.md) |
| 3 | 默认 shell 在 HAP bundle 里 | `fork/exec .../bundle/.../bash: permission denied` | 自签名 bash 放 `~/opt/bin` 并前置 PATH → [03](docs/port/03-bash-exec-denied.md) |

三条缺一不可。装完之后：

```sh
$ agy -p "运行 echo hello"
Command exited with code 0.
Command output:
hello
```

---

## 安装

```sh
bash scripts/install.sh          # 幂等；已安装会跳过下载
bash scripts/install.sh --force  # 升级：下载最新版并重新打补丁+签名
bash scripts/verify.sh           # 五项本地自检
```

`install.sh` 依次做：

1. 按 manifest 拉 `linux_arm64_musl` 版 agy，校验 SHA-512
2. `scripts/repatch.py` 定位并 NOP 掉内核版本检查（不写死偏移，换版本可用）
3. `binary-sign-tool -selfSign 1` 自签名（鸿蒙要求所有 ELF 带签名）
4. 复制并签名一份 bash 到 `~/opt/bin/bash`
5. 生成启动器 `~/opt/bin/agy`
6. 往 `~/.zshrc` 追加 PATH（已有则跳过）

依赖：`curl`、`tar`、`python3`、`/data/service/hnp/bin/binary-sign-tool`（后两个鸿蒙 PC 自带）。

---

## 代价与限制

| 项 | 状态 |
|---|---|
| 沙箱隔离 | **不可用**。鸿蒙对 `clone(CLONE_NEW*)` 直接 SIGSYS，没有降级机会 |
| 工具确认 | **全部免确认**（同一个开关控制，无法只关沙箱、保留确认） |
| 自动更新 | **必须关闭**（启动器已设 `AGY_CLI_DISABLE_AUTO_UPDATE=1`）。否则后台更新会替换成未签名二进制，下次启动直接 `Permission denied`（126） |
| 平台判定 | 不影响。agy 是 Go 静态二进制，`GOOS=linux` 本来就对 |
| 网络 | 需能连 `*.googleapis.com`；国内网络偶发 `EOF`，重试即可 |
| 架构 | 仅 aarch64（鸿蒙 PC / 2in1） |

---

## 目录

```
ohos-agy/
├── README.md
├── docs/
│   ├── port/                                  # 移植实现文档（本工程核心）
│   │   ├── 01-kernel-too-old.md
│   │   ├── 02-seccomp-namespace.md
│   │   ├── 03-bash-exec-denied.md
│   │   └── 04-troubleshooting.md
│   ├── antigravity-harmonyos-feasibility.md   # 可行性研究（App/IDE 视角）
│   ├── feasibility-summary.md                 # 上述研究的摘要版
│   ├── evidence-antigravity-package.md        # 官方包体实测证据
│   ├── gate0-experiments.md                   # Gate 0 实验清单
│   ├── hmskills-findings.md                   # 技能格式兼容性
│   └── agy-on-harmonyos.md                    # 早期方案：Linux 主机 + SSH（历史）
├── scripts/
│   ├── install.sh
│   ├── verify.sh
│   ├── repatch.py            # 按字符串自动定位补丁点
│   └── probe_seccomp.py      # 枚举本机被 seccomp 拦截的 syscall
└── templates/
    ├── agy.launcher.sh
    └── zshrc.snippet
```

> 研究缓存（约 1.8 GB 的官方包体与解包产物）**不入库**，复现方法见 [evidence 文档](docs/evidence-antigravity-package.md)。

---

## 已验证能力（nextPDF 工程实测）

- 读代码：正确识别 Hvigor + ohpm、Stage 模型、`entry` 模块、`EntryAbility`
- 执行命令：`git status`、`ls`、构建脚本
- 全量构建：`clean` 5.6s + `build` 18.1s（CompileArkTS 7.3s）→ 产出签名 HAP

---

## 免责

- `agy` 是 Google 的**闭源**二进制（`github.com/google-antigravity/antigravity-cli` 只有 README 与 issue 模板，无源码、无 LICENSE 文件）。
- 本工程只做**二进制补丁 + 自签名 + 启动器**，不重新实现、不修改功能逻辑、不规避授权。
- 不随仓库分发任何 Google 二进制；`install.sh` 从 Google 官方发布端点下载。
- Antigravity 是 Google LLC 的商标。本工程与 Google 无关联，名称仅用于说明移植对象。
- 关掉沙箱意味着 agent 对本机文件系统有完全控制权，请自行评估风险，仅限个人在本机使用。
- 自签名会降低系统完整性保证，仅建议在开发机上使用。

## 许可

代码与文档：MIT，见 [LICENSE](LICENSE)（© 2026 kehahn）。
