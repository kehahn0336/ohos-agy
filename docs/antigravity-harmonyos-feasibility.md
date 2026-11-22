# Google Antigravity 迁移 HarmonyOS 可行性报告

> **适用范围**：本文评估的是 **Antigravity 桌面应用 / IDE**（Electron 壳 + `language_server`），**不含 CLI**。
> CLI（`agy`）已在鸿蒙本机跑通，见 [port/](port/)；两者是不同产物：App 的 LS 是动态链接 glibc，CLI 的 musl 构建是静态的。

> 评估日期：2026-11-20  
> 评估对象：Google Antigravity App **2.33.0**，官方 Linux ARM64 包（Electron **44.9.1**，2026-11-17 构建）  
> 平台基线：HarmonyOS PC（HongMeng Kernel 1.13.0，aarch64）；Electron for OpenHarmony **V40**（Electron 40.1.0 / Chromium 144 / Node 24.11.1）  
> 依据：`hmskills` 移植知识库（16 个 skill、139 个坑位）+ Antigravity 包体静态分析 + 本机 DSH 移植实测 + Antigravity 官方文档/ToS

---

## 0. 执行摘要

**结论：Antigravity 本体不能“原样迁移”；能迁移的是它的 agent 形态、技能体系和交互方式，而且需要重建，不是移植。**

三条决定性事实：

1. **Antigravity App 是一个“薄壳”**。`app.asar` 只有 6.47 MB，里面没有 `.node`、没有 `.wasm`、没有 ripgrep/node-pty；它的职责是启动 `resources/bin/language_server`，然后打开 `https://127.0.0.1:<LS 端口>/`。**界面、agent、工具全在 LS 里，不在 Electron 里。**
2. **`language_server` 是一枚 203 MB 的 Go 1.28 二进制**，动态链接 glibc（`/lib/ld-linux-aarch64.so.1`、`libc.so.6`、GLIBC_2.17–2.26）。鸿蒙是 musl 用户态，没有这个 loader；而且应用进程禁止 `exec` 自带 ELF。**即使把 Electron 壳搬过去，也起不了 LS；LS 起不来，连主界面都不会创建。**
3. **Google 的 ToS 明确禁止第三方客户端**。Antigravity Additional Terms 第 6 条：不得“using the Service in connection with products not provided by us”，并点名“用第三方软件/工具/服务访问 Service（如 OpenClaw + Antigravity OAuth）属于违约”。**任何鸿蒙端第三方 Antigravity 客户端，即使技术上跑通，也不具备上架合法性。**

因此：

| 目标 | 判定 |
|---|---|
| 原样搬 Antigravity App / IDE / CLI / SDK | ❌ 不可行（技术 + 法律双重否决） |
| 只搬 `app.asar` 做“鸿蒙版 UI” | ❌ 无意义（没有 LS 就没有界面/agent） |
| 在鸿蒙上重建 Antigravity 类 agent | ✅ 可行，但是重写，周期 4–6 个月起 |
| 在鸿蒙上“使用”Antigravity | ✅ 可行，走官方 Remote Control 网页版，零移植 |
| 迁移 `SKILL.md` 技能 | ✅ 直接可用（开放标准，`hmskills` 同格式） |

---

## 1. 评估对象与方法

### 1.1 为什么选 Antigravity App，而不是 IDE

Antigravity 2.0 之后有五个 surface：App、CLI、IDE、编辑器扩展、Python SDK。它们共享同一套 agent harness，但 App 是当前的主形态（Agent Manager 演化成的独立桌面指挥中心）。本报告以 **App 2.33.0 Linux ARM64 官方包**为主样本，因为它：

- 是官方直接分发的完整桌面端，能代表“把 Antigravity 搬上鸿蒙”的真实对象；
- 有 Linux ARM64 产物，架构与鸿蒙 PC 一致（aarch64），排除了“架构不对”的干扰；
- 能直接观察 Electron 壳与 `language_server` 的分工。

### 1.2 方法

1. **读 `hmskills`**：`harmonyos-porting` 的三过滤、`hard-constraints.md` 的 exec/dlopen 实测、`harmonyos-electron-porting` 的 Electron 平移边界、`harmonyos-node-inprocess-host` 的 Node 宿主替代路线。
2. **拆官方包**：从 `storage.googleapis.com/antigravity-public/.../linux-arm/Antigravity.tar.gz` 下载 203,199,363 B 的 tarball，解包后做 `file` / `readelf` / `strings` / asar 解析。
3. **读官方文档与 ToS**：安装要求、skills、MCP、browser、Remote Control、SDK、Terms。
4. **对照本机既有实测**：`dsh-desktop-ohos` 在 HarmonyOS 2in1 上验证过 Electron 40 的 spawn / utilityProcess / HNP 行为。

### 1.3 “迁移”的四种含义

后文统一按这四种含义讨论，避免“能不能迁”各说各话：

- **M1 产品平移**：把 Antigravity 的二进制/安装包搬到鸿蒙运行；
- **M2 代码复用**：把 Antigravity 的 JS/Go/Python 代码嵌入鸿蒙应用；
- **M3 能力重建**：在鸿蒙上重新实现 agent loop、工具、UI；
- **M4 远程使用**：鸿蒙只做客户端，agent 跑在别的机器/云上。

M1、M2 不可行；M3 可行但工作量大；M4 可行且最快。

---

## 2. Antigravity 的真实架构（实测）

### 2.1 包体结构

官方 Linux ARM64 tarball 解包后（`Antigravity-arm64/`）：

| 路径 | 大小 | 作用 |
|---|---:|---|
| `antigravity` | 220.9 MB | Electron 44.9.1 主程序（ELF，glibc 动态链接） |
| `resources/app.asar` | **6.47 MB** | Electron 壳：窗口、菜单、托盘、SSH、更新、Host Bridge、拉起 LS |
| `resources/bin/language_server` | **203.0 MB** | **真正的产品**：UI 服务 + agent runtime + 工具 + 云端协议 |
| `resources/app.asar.unpacked/` | 17 MB | 只有 `chrome-devtools-mcp` 一个 Node 包（含 skills），无原生 `.node` |
| `resources/app-update.yml` | — | `electron-updater`，generic 更新源 |
| `version` | — | `44.9.1`（Electron 版本） |

`app.asar` 内部统计（解析 asar header）：

- 1156 个文件，解压后 20.4 MB；
- `dist/` 165 个文件，`node_modules/` 20 个包；
- **0 个 `.node`，0 个 `.wasm`**；
- 依赖只有 `@bufbuild/protobuf`、`@connectrpc/connect`、`@connectrpc/connect-node`、`chrome-devtools-mcp`、`electron-log`、`electron-updater`、`js-yaml`。

这说明：**Electron 侧不承载 agent 逻辑，也不承载原生工具；它只是 LS 的启动器和窗口壳。**

### 2.2 启动链路

`app.asar` 的 `dist/main.js` 在 `app.whenReady()` 后：

1. 初始化 `electron-log`、storage、settings；
2. 启动 Host Bridge（供 LS 回调宿主能力）；
3. `startAndMonitorLanguageServer(...)`：
   - `languageServer.js` 用 `child_process.spawn` 拉起 `resources/bin/language_server`；
   - 传 `--standalone`、`--app_data_dir`、`--https_server_port`、`--csrf_token`、`--api_server_url https://generativelanguage.googleapis.com`、`--cloud_code_endpoint https://daily-cloudcode-pa.googleapis.com`、`--enable_sidecars`；
   - 等待 LS 在 stdout 打印 `listening on ... port at N`，超时 **60 秒**；
4. 拿到端口后，创建窗口加载 `https://127.0.0.1:<port>/`；
5. 如果 LS 起不来：`dialog.showErrorBox('Startup failed', msg)` → `app.quit()`，**不会创建主窗口**。

关键代码位置（解包后的可读 JS）：

- `dist/languageServer.js:273`：`_lsProcess = spawn(spawnCmd, spawnArgs, ...)`；
- `dist/lsDefaults.js`：LS 的 `--standalone` 参数表；
- `dist/constants.js`：`WINDOW_ORIGIN = 'https://127.0.0.1'`；
- `dist/main.js:519-556`：LS 启动失败 → 错误框 → 退出；
- `dist/main.js:592-595`：**LS 成功后**才 `createWindow(url)`。

所以：**“把 app.asar 搬上鸿蒙”最多得到一个会弹 `language_server binary not found` 或 `Startup failed` 的空壳，不会有 Antigravity 界面。**

### 2.3 `language_server` 是什么

`file` / `readelf` 结果：

```
ELF shared object, 64-bit LSB arm64, dynamic (/lib/ld-linux-aarch64.so.1), stripped
NEEDED: libresolv.so.2, libpthread.so.0, libm.so.6, libdl.so.2, librt.so.1, libc.so.6
GLIBC_2.17 / 2.18 / 2.25 / 2.26
Go: go1.28-20261102-RC00
```

它不是“语言服务器”意义上的 LSP 小工具。`strings` 里能看到它包含：

- `google3/third_party/jetski/...`：agent / Cortex / trajectory / rehydration；
- `cloudcode`、`v1internal`：Google Cloud Code 后端协议；
- `SKILL.md`、`mcp_config.json`、`plugin`、`marketplace`：技能/插件/MCP；
- `search_ripgrep.go`、`ANTIGRAVITY_DISABLE_EMBEDDED_RIPGREP`：搜索；
- `MOCK PTY`、terminal、sidecar、worktree、git、browser_tools、computer use；
- `--standalone`、`--cloud_code_endpoint`、`--app_data_dir`、`--subclient_type hub`；
- OAuth（`accounts.google.com`）、模型（Gemini 4 / Claude）、远程会话、SSH。

**LS = Antigravity 的全部**：它既提供 Web UI，又跑 agent，又执行工具，又连 Google 后端。Electron 只是它的“浏览器 + 窗口管理器”。

### 2.4 其他 surface 同样绑死 LS

| Surface | 形态 | 与 LS 的关系 |
|---|---|---|
| Antigravity App | Electron 44.9.1 | 启动本地 LS，窗口加载 LS 的 Web UI |
| Antigravity IDE | VS Code fork（公开 issue 显示 2.1.1 基于 VS Code 1.107、Electron 39.2.3） | Electron 主进程 + Extension Host 各 spawn 一份 `language_server` |
| Antigravity CLI (`agy`) | 单文件 Go 二进制（1.1.28 实测 192 MB，glibc 动态链接） | 自带 agent runtime，仍连 Google Cloud Code |
| Antigravity SDK | Python 3.10+ 库 | `Agent` 类负责 **binary discovery**，本地 runtime harness |
| 编辑器扩展 | VS Code / JetBrains / VS / Zed / Xcode / Eclipse | 通过 LS/ACP 连接同一 runtime |

**共同点：agent 能力不在 JS/Python 层，而在一个本地二进制 runtime 里。** 这正是鸿蒙最不能提供的形态。

### 2.5 官方平台要求

- Linux：**glibc >= 2.28，glibcxx >= 3.4.25**（Ubuntu 20+ / Debian 10+ / Fedora 36+ / RHEL 8+）；
- 提供 x64 和 **ARM64** tarball；
- 鸿蒙是 **musl** 用户态，不是 glibc 发行版；没有 `/lib/ld-linux-aarch64.so.1`。
- App 更新走 `electron-updater`（generic 源）；鸿蒙不支持 `autoUpdater`，只能走应用市场。

---

## 3. HarmonyOS 的硬约束（来自 hmskills）

### 3.1 运行时三过滤

`hmskills/harmonyos-porting/references/hard-constraints.md` 的实测结论：

| 能力 | 结论 | 依据 |
|---|---|---|
| 应用进程 `exec` 自带 ELF | ❌ | 三路对照：`/system/bin/toybox` SUCCESS；cache/filesDir 自建 ELF EACCES；共享区自签 ELF EPERM |
| `dlopen` HAP 内 `libs/arm64-v8a/*.so` | ✅ | 唯一可靠的原生分发通道 |
| `dlopen` 数据目录 `.so` | ❌ | ENOENT，linker namespace 隔离 |
| 运行时下载/热更新插件 | ❌ | 分发形态锁死为整包 |
| `.so` / ELF 不签名 | ❌ | 未签名 `.so` 报 `Error loading shared library ...`；ELF 报 `Permission denied` |
| shell 态 `exec` 自签 ELF | ✅ | 开发态可以；**不等于应用态可以** |

关键区分：**`hdc shell` 里能跑 ≠ HAP 应用里能跑。** Antigravity 的 LS 即使能在鸿蒙 shell 里被 `binary-sign-tool` 签名后运行，也不能作为应用的一部分被拉起。

### 3.2 Electron for OpenHarmony 的能力边界

`hmskills/harmonyos-electron-porting` 的 V40 实测：

| 项 | 结论 |
|---|---|
| 版本 | Electron 40.1.0 / Chromium 144 / Node 24.11.1，`process.platform === 'ohos'` |
| 架构 | 仅 **arm64-v8a**；无 x86_64，模拟器装不上 |
| 设备 | 只适合 `2in1` / `tablet`；手机竖屏体验差 |
| `child_process.spawn` / `fork` | ❌ 无适配层；`ProcessAdapter` 只服务 Chromium 渲染子进程 |
| `utilityProcess.fork` | ❌ 真机 `exit=5`，无 IPC |
| Node 原生 addon | ⚠ 需按华为文档重编并链 `libelectron.so`；预编译 `.node` 不可用 |
| `node-pty` | ⚠ `@lydell/node-pty` 无 ohos 平台包；需自造平台包或源码编译 |
| `autoUpdater` | ❌ 无适配，改用应用市场 |
| 包体 | 运行时约 300 MB；HAP 下限 ~130 MB，未优化 400 MB+ |
| safeStorage | ⚠ 半成品：能加密，`decryptString` 认不出自己的产物 |
| DevTools | ✅ 内嵌面板可用；主进程日志不进 hilog，改看 `[WebEngine]` |
| 命令行参数 | ❌ 不能从外部传，只能代码内平台分支 |

本机 `dsh-desktop-ohos` 的 Gate 0 还补了更硬的真机数据：

| 实验 | 结果 |
|---|---|
| `spawn(process.execPath)`（`/system/bin/appspawn`） | `EACCES` |
| `spawn(resourcesPath/electron)` | `EACCES`（6584 B 的 ELF 壳） |
| `utilityProcess.fork(script)` | `exit=5`，无 IPC |
| `spawn('/data/service/hnp/bin/node')` | 进程能起（有 pid），随后**静默挂死**（无 error/exit/IPC） |
| `spawn(hnp bash + node + IPC)` | 未打通 |

**结论：任何“Electron 主进程 + 独立 sidecar 进程”的架构，在鸿蒙 HAP 里都不可保留。** Antigravity 恰好就是这个架构。

### 3.3 替代路线存在，但都是“重建”

| 路线 | 能力 | 代价 |
|---|---|---|
| Node 进程内宿主（`harmonyos-node-inprocess-host`） | libnode 装 HAP，`dlopen` 胶水拉起，Node 侧跑文件/会话/HTTP/插件 | 无 Chromium；`--jitless` 下 WASM 不可用；原生 addon 要进 HAP `libs/` 并签名；不能 exec |
| ArkWeb 包壳（`harmonyos-arkweb-shell`） | 纯 Web 应用 → HAP | 只适合零网络依赖；ESM/Service Worker/CORS 有坑；不能跑 Node |
| ArkUI 原生 | 系统能力、UI、性能最好 | 要重写 UI 与工具层 |
| Electron 平移（`harmonyos-electron-porting`） | 保留 Electron 应用 JS | 只能跑 JS 层；sidecar/addon/终端/搜索/Git 全部受限 |
| 混合远程 | 鸿蒙做 UI，Linux/云做重活 | 依赖网络/主机；不是本地 agent |

---

## 4. 逐层可行性矩阵

把 Antigravity 拆成 14 层，对鸿蒙能力逐项判定：

| # | Antigravity 层 | 它依赖什么 | 鸿蒙侧能力 | 判定 |
|---|---|---|---|---|
| 1 | Electron 壳（窗口/菜单/托盘） | Electron 44.9.1 | Electron for OHOS 40.1.0 | ⚠ 版本差 4 个大版本；壳可改，但没 LS 无意义 |
| 2 | `app.asar` 启动逻辑 | Node/Electron API、`spawn` | 无 `spawn` 适配 | ❌ 起 LS 这一步就断 |
| 3 | `language_server` 进程 | glibc ELF、`exec`、本地 HTTP/HTTPS | musl、禁 exec | ❌ **硬否决** |
| 4 | Web UI（由 LS 提供） | LS 的 HTTPS 端口 | 无 LS；ArkWeb 可渲染但无后端 | ❌ 没有 LS 就没有 UI |
| 5 | Agent harness（Cortex/轨迹/子 agent） | LS 内部 Go 代码 | 无源码；需重写 | ❌ 原样；✅ 重写 |
| 6 | 终端工具 | LS → PTY/系统 shell | node-pty 需自编译；只能调系统 shell；不能 exec 自带二进制 | ⚠ 可做但受限 |
| 7 | 文件搜索 | 内嵌 ripgrep / Go 搜索 | 无 `rg` 可 exec；需 JS/Go 重写 | ⚠ 可做 |
| 8 | Git / worktree / 子 agent 隔离 | `git` CLI / 内嵌实现 | 无 `git` 可 exec；需 libgit2/isomorphic-git | ⚠ 可做，工程量大 |
| 9 | 浏览器子 agent | 内嵌 Chromium（App）/ Chrome 144+（IDE/CLI） | ArkWeb 可自动化；无 Chrome | ⚠ 需重写浏览器工具 |
| 10 | MCP stdio | `spawn(command)` 启动本地 MCP server | 禁 exec | ❌ 原样；✅ 远程 HTTP MCP |
| 11 | MCP Streamable HTTP | 网络 | 可用 | ✅ |
| 12 | Skills（`SKILL.md`） | 文件系统 + prompt | 可用 | ✅ 直接复用 |
| 13 | Google OAuth / 模型后端 | accounts.google.com、cloudcode、Gemini | 网络可达性/合规性不确定；ToS 限制 | ❌/⚠ 最大不确定性 |
| 14 | 自动更新 / 崩溃上报 / 签名上架 | electron-updater / crashpad / AGC | 无 autoUpdater；HAP 签名/AGC | ⚠ 需改 |

**结论：**

- 第 3 层是**单点硬否决**：LS 不能在鸿蒙应用里跑。
- 第 4/5/6/7/8/9/10 层都依赖第 3 层；LS 不在，全部失效。
- 只有第 12 层（Skills）可以原样搬；第 11 层（远程 MCP）可用；第 1 层壳可搬但没用。
- 所以“平移”最多得到 1 + 12 层，拿不到 3–10 层；**产品价值为 0**。

---

## 5. 四条路线对比

### 路线 A：Remote Control 网页版（最快，零移植）

**做法**：在 Linux/macOS/Windows 主机上安装并登录 Antigravity App 或 CLI，打开 Remote Control；鸿蒙浏览器访问 `https://antigravity.google.com/`，同 Google 账号登录，即可驱动主机上的会话。

**优点**：

- 官方支持，不改一行代码；
- 鸿蒙侧只要有现代浏览器（ArkWeb/Chrome 均可）；
- 保留完整的 Antigravity agent、工具、浏览器、技能；
- 主机上的重活（终端、Git、构建）不受鸿蒙 exec 限制。

**限制**：

- 必须有另一台常开主机；不是本地/离线；
- 需要 Google 账号与网络可达；
- 鸿蒙侧只是 Web 客户端，不能调用本地文件/终端（除非用 Remote Control 的会话能力）；
- 如果要包装成 HAP，只是 ArkWeb 包壳，注意 Google 品牌/ToS，不要伪装成“鸿蒙版 Antigravity”。

**适用**：现在就想在鸿蒙 PC 上用 Antigravity 的个人/团队。

**工作量**：0（浏览器）～ 3 天（ArkWeb 壳 + 图标/登录引导）。

### 路线 B：原生重建“Antigravity 类” agent（推荐长期）

**做法**：在鸿蒙上重写 agent harness + 工具层 + UI，复用 Antigravity 的产品概念、`SKILL.md` 技能、MCP 协议和 prompt/tool schema；模型走 Gemini API 或其他 LLM。

**能复用的**：

- `SKILL.md` 开放标准（`hmskills` 就是 16 个鸿蒙技能，可直接变成 agent 技能）；
- MCP（远程 Streamable HTTP 优先）；
- Antigravity 的交互范式：Agent Manager、会话、artifacts、diff、browser 子 agent、权限预设；
- SDK 的 API 设计（Agent/LocalAgentConfig/tools/skills/MCP/policies/subagents）作为架构参考。

**必须重写的**：

- agent loop（模型调用、工具调用、上下文管理、压缩、重试、流式）；
- 工具层（文件、搜索、编辑、终端、Git、浏览器、MCP、子 agent）；
- UI（ArkUI 或 ArkWeb）；
- 权限/沙箱/审批；
- 模型网关与凭据；
- 打包/签名/上架。

**适用**：要做鸿蒙原生 agent 产品、且能接受 4–6 个月投入的团队。

**工作量**：Gate 0 2 周；MVP 8–10 周；Beta 4–5 个月；产品 6–9 个月（3–5 人）。

### 路线 C：Electron 平移 Antigravity App（不推荐）

**做法**：把 `resources/app.asar` 塞进 Electron for OHOS 的 `resources/app`，用 V40 运行时启动。

**会发生什么**：

1. `app.asar` 的 `main.js` 找 `resources/bin/language_server`；
2. 找到也起不来：`spawn` 在鸿蒙 Electron 里无适配/静默挂死；LS 本身是 glibc ELF；
3. 找不到/起不来：`language_server binary not found` 或 60 秒超时 → `Startup failed` → 退出；
4. 即使你把 LS 换成远程服务，UI 的 Host Bridge、本地文件、终端、浏览器、OAuth 仍然缺；
5. 即使全部 hack 通，Google ToS 第 6 条也不允许第三方客户端。

**结论**：**不要做。** 这不是“难”，是“方向错”。

**工作量**：2–4 周能得到一个报错框；之后无底洞。

### 路线 D：混合远程 runtime（可产品化）

**做法**：鸿蒙端做 UI/审批/文件浏览；Linux/云 worker 跑 agent runtime（自研或开源 harness），通过 WebSocket/HTTP 通信；重活（终端、Git、构建、浏览器）在 worker 上执行。

**优点**：

- 绕开鸿蒙 exec/原生工具限制；
- 接近 Antigravity 的 Remote Agents/Remote Control 架构；
- 可做团队共享、长任务、定时任务。

**限制**：

- 需要后端/运维；
- 网络依赖；
- 文件同步/权限模型复杂；
- 如果 worker 跑的是 Antigravity 本体，仍受 ToS 限制；跑自研 runtime 才可控。

**适用**：企业/团队、重任务、云端开发场景。

**工作量**：客户端 4–6 周；后端 + 产品化 3–6 个月。

### 路线 E：CLI 放 Linux 主机，鸿蒙 SSH 用（“只想跑 agy”的答案）

**做法**：官方 `agy` 装在 Linux 主机/云主机上；鸿蒙用 `ssh -t` 登录过去，在远端终端跑 `agy`，走官方 Remote SSH OAuth：远端打印授权 URL → 鸿蒙浏览器登录自己的 Google 账号 → 回终端粘贴授权码。

**为什么不能本机直接跑**：

- 官方 `agy` 1.1.28 是 **192 MB、Go 1.28、动态链接 glibc** 的二进制（`/lib/ld-linux-aarch64.so.1`、GLIBC_2.17–2.26）；
- 鸿蒙只有 musl loader，没有 glibc；
- 我自带 Debian arm64 的 glibc 2.41/2.28 loader 试过：loader 能启动，但映射目标程序时统一报 `failed to map segment from shared object`，连签名后的 Debian `/bin/echo` 也一样；
- 所以“签名后直接在鸿蒙 shell 跑”也不成立。

**限制**：

- 需要一台 Linux 主机/云主机（glibc ≥ 2.28）；
- 浏览器子 agent 需要那台主机上有 Chrome 144+；鸿蒙侧不需要；
- token 在 SSH 模式下落到 `~/.gemini/antigravity-cli/antigravity-oauth-token`，注意权限；
- 网络需可达 Google 登录与 Cloud Code 后端。

**结论**：这是“只想用 `agy` + 自己的账号”的最佳可用方案；不是鸿蒙本地产品，但功能完整、合规（官方 CLI，不是第三方客户端）。

### 路线对比表

| 路线 | 时间 | 成本 | 产物 | 风险 | 适合 |
|---|---|---|---|---|---|
| A Remote Control | 0–3 天 | 极低 | 鸿蒙浏览器里的 Antigravity | 依赖主机/Google 网络 | 马上用 |
| B 原生重建 | 4–6 个月 | 高 | 鸿蒙原生 agent 产品 | 模型质量/工程量 | 做产品 |
| C Electron 平移 | 2–4 周起，实际无底 | 中高 | 报错框/残缺壳 | 技术+法律双死 | 不建议 |
| D 混合远程 | 3–6 个月 | 高 | 鸿蒙客户端 + worker | 后端/运维 | 企业/团队 |
| E Linux + SSH | 0–1 天 | 低 | 远端 `agy`，鸿蒙做终端 | 依赖 Linux 主机/网络 | “只想跑 agy” |

---

## 6. 推荐路线 B 的参考架构

### 6.1 总体图

```
┌─────────────────────────────────────────────────────────────┐
│ HarmonyOS HAP（arm64，2in1/tablet）                          │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ UI 层：ArkUI + ArkWeb                                  │  │
│  │  Agent Manager / 会话 / artifacts / diff / 浏览器侧栏  │  │
│  └──────────────────────────┬────────────────────────────┘  │
│                             │ 进程内 RPC / HTTP              │
│  ┌──────────────────────────▼────────────────────────────┐  │
│  │ Agent Runtime（Node 进程内宿主 或 ArkTS）              │  │
│  │  ├─ 模型网关（Gemini API / DeepSeek / Qwen，SSE）      │  │
│  │  ├─ Agent Loop（工具调用、上下文、压缩、重试）          │  │
│  │  ├─ 工具注册表（fs / search / edit / terminal / git）  │  │
│  │  ├─ 浏览器工具（ArkWeb 自动化）                        │  │
│  │  ├─ MCP 客户端（远程 HTTP 优先；本地 in-process）       │  │
│  │  ├─ Skills 加载器（SKILL.md，渐进式披露）               │  │
│  │  ├─ 子 agent（异步任务/Worker，不用 OS 进程）           │  │
│  │  └─ 权限/审批/审计                                     │  │
│  └──────────────────────────┬────────────────────────────┘  │
│                             │                                │
│  ┌──────────────────────────▼────────────────────────────┐  │
│  │ 系统能力层：Node fs / ArkTS picker / HUKS / PTY / ArkWeb│  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 6.2 运行时选型

| 选项 | 优点 | 缺点 | 建议 |
|---|---|---|---|
| **Node 进程内宿主**（libnode 装 HAP） | npm 生态、MCP SDK、SSE、fs、测试工具全可用；`hmskills` 有现成路线 | 无 Chromium；`--jitless` 下 WASM 不可用；原生 addon 要进 HAP `libs/` 签名；不能 exec | **首选**，适合 agent runtime |
| ArkTS 原生 | 系统集成最好、包体小、权限模型顺 | 生态少、模型/流式/工具库要自己写；大量代码 | UI + 系统桥接；agent 核心可放 Node |
| Electron for OHOS | 可直接复用 Web UI/Electron API | 包体 300MB+；无 spawn；addon 受限；仍是 sidecar 思路 | 只在“必须复用现成 Web 前端”时考虑 |

**推荐**：**Node 进程内宿主跑 agent + ArkUI 做外壳**。UI 用 ArkUI 原生（Agent Manager、会话、审批、diff），需要富文本/HTML artifact 时嵌 ArkWeb。这样既避开 Electron 的包体与 spawn 限制，又能用 Node 生态。

### 6.3 工具层落地

| 工具 | 鸿蒙做法 | 关键坑 |
|---|---|---|
| 读/写/列文件 | Node `fs` + ArkTS picker；工作区目录用持久 URI | picker 临时授权不跨重启（P-097）；需 `fileAccessPersist` |
| 搜索 | JS 遍历 + 索引；或把 Go/Rust 搜索编成 HAP `.so` 走 NAPI | 不能 exec ripgrep；大仓库需索引/增量 |
| 编辑 | 文本 diff/patch；大文件分块 | 编码/换行/只读文件 |
| 终端 | `node-pty`（microsoft 版）源码编译进 HAP；只 exec **系统可信 shell**（`/system/bin/sh` 或 HNP bash） | 应用态不能 exec 自带二进制；HNP 只适合开发态；PTY 需真机验证 |
| Git | `isomorphic-git`（纯 JS）或 libgit2 编 `.so` | 不能 exec `git`；worktree/submodule 要另做 |
| 浏览器 | ArkWeb `runJavaScript` / `javaScriptProxy`；开发态可 `hdc fport` + CDP | 无 Chrome；跨域/登录态/截图要自己做 |
| MCP | 远程 Streamable HTTP；本地 stdio 改成进程内 JS MCP server 或“假 CLI + 队列” | 不能 spawn 本地 MCP server；stdio 协议要自己桥 |
| Skills | 解析 `SKILL.md` YAML frontmatter；启动时列 name/description；命中后读全文 | 技能目录放 `resfile` 或工作区 `.agents/skills`；渐进式披露 |
| 子 agent | 同进程异步任务 + 独立上下文；重活可丢给 Worker | 无 OS 进程隔离；内存/取消/超时要自己管 |
| 模型 | HTTPS/SSE 调 Gemini API / Vertex / 其他；工具调用用 JSON Schema | 网络合规、Key 安全、流式解析、重试/限流 |

### 6.4 技能迁移（最快的一步）

Antigravity 的 Skills 是开放标准：`SKILL.md` + YAML frontmatter（`name`、`description`），渐进式披露；目录为 `<workspace>/.agents/skills/` 和 `~/.gemini/config/skills/`。

`hmskills` 的格式完全一致（`SKILL.md` + `references/` + 触发关键词），因此：

- 可以把 `hmskills` 的 16 个移植技能直接作为鸿蒙 agent 的技能库；
- 可以把 `hmskills-cli` 的 40+ 个应用开发技能（ArkTS/ArkUI/Kit）作为第二层技能；
- 每个技能的 `description` 就是触发词，适合做渐进式披露；
- 这是**唯一可以“原样迁移”的资产**，也是重建路线里最快能见效的部分。

### 6.5 权限与安全

- 工作区目录白名单 + 每次会话显式授权；
- 命令审批：只允许系统 shell 的白名单命令；危险命令（`rm -rf`、`dd`、`mkfs`）默认拒绝；
- 网络出口：模型 API、MCP 域名白名单；禁止任意 URL；
- 凭据：HUKS/Asset Store，不落明文；日志脱敏；
- 审计：工具调用、文件变更、网络请求留痕；
- 上架：隐私政策、权限说明、数据处理声明、AGC 审核。

### 6.6 打包与分发

- HAP，`deviceTypes: ["2in1","tablet"]`；arm64；
- 包体目标：150–300 MB（Node 宿主 + 前端 + 技能）；不要背 Chromium；
- 签名：`assembleApp` + `hap-sign-tool`；参考 `harmonyos-hvigor-signing`；
- 更新：应用市场，不做 autoUpdater；
- 合规：不要用 Google/Antigravity 商标做产品名；不要打包 Google 二进制。

---

## 7. 工作量与里程碑

### 7.1 Gate 0（2 周，Go/No-Go）

| # | 实验 | 通过标准 |
|---|---|---|
| G0-1 | 在鸿蒙 Electron 40 里加载 Antigravity `app.asar` | 确认在 LS 拉起处失败；记录错误（预期失败，用于钉死结论） |
| G0-2 | 鸿蒙 shell 直接跑 `language_server` | 确认 `No such file or directory`（缺 glibc loader）；记录 |
| G0-3 | Node 宿主 HAP：模型 SSE + 文件读写 + 搜索 + Skills | 真机跑通，P95 延迟可接受 |
| G0-4 | 终端：node-pty + `/system/bin/sh` | 能起 PTY、能执行 `echo`/`ls`；不能 exec 自带二进制 |
| G0-5 | 浏览器：ArkWeb + JS 注入/截图/点击 | 能完成一次表单填写 + 截图 |
| G0-6 | MCP 远程 HTTP + 技能加载 | 能列出工具、调用一次、命中一个 `SKILL.md` |
| G0-7 | 合规：Gemini API/Google ToS/AGC | 法务/合规书面结论 |

**Go 条件**：G0-3、G0-4、G0-5 至少两项通过；G0-7 无否决。  
**No-Go**：终端完全不可用 + 模型不可合法接入 → 退回“只读代码助手”或远程方案。

### 7.2 里程碑

| 阶段 | 内容 | 工期 | 团队 |
|---|---|---|---|
| Gate 0 | 上述 7 项 spike | 2 周 | 2 人 |
| MVP | 单 agent：会话、读写、搜索、终端、模型、Skills、审批 | 8–10 周 | 2–3 人 |
| Beta | 多 agent、artifacts、diff、浏览器、MCP、权限、打包 | 8–10 周 | 3–4 人 |
| 产品化 | 稳定性、性能、安全、合规、AGC、文档 | 8–12 周 | 3–5 人 |
| 合计 | — | **6–9 个月** | 3–5 人 |

> 如果只做“能演示的 agent”（单会话、读写、搜索、模型、技能），2–3 个月可以出 Demo；不要拿 Demo 当产品承诺。

### 7.3 成本粗算

- 人力：3–5 人 × 6–9 个月；
- 模型：按 token 计，取决于用户量；Gemini/Claude 成本高于国内模型；
- 基础设施：如果走混合远程，需要 worker/存储/带宽；
- 合规：法务、隐私、上架材料；
- 维护：模型/API 变更、系统版本升级、技能库更新。

---

## 8. 风险登记

| # | 风险 | 等级 | 说明 | 缓解 |
|---|---|---|---|---|
| R1 | 应用态禁 exec | **致命** | LS/CLI/MCP stdio 全部依赖 spawn | 架构上改成进程内/远程，不 exec |
| R2 | 无 glibc | **致命** | Antigravity 官方 Linux 包无法在鸿蒙运行 | 不搬二进制；重写或远程 |
| R3 | Google ToS 第 6 条 | **致命** | 第三方客户端访问 Service 属违约 | 不碰 Antigravity OAuth/后端；用 Gemini API 或国内模型 |
| R4 | 模型可达性/合规 | 高 | Gemini 在部分网络/地区不可用；数据出境 | 多模型网关；国内模型；合规评估 |
| R5 | 终端能力不足 | 高 | 无法 exec 自带二进制；只能系统 shell | 限制为“工作区命令”；远程 worker 兜底 |
| R6 | 浏览器自动化 | 中高 | 无 Chrome；ArkWeb 能力/调试接口有限 | 先做 JS 注入 + 截图；必要时 Electron/远程浏览器 |
| R7 | Git/worktree | 中高 | 无 git CLI；子 agent 隔离难 | isomorphic-git/libgit2；先不做 worktree |
| R8 | 原生 addon | 中 | node-pty 等需自编译/签名 | 按 `harmonyos-node-toolchain` 编译进 HAP `libs/` |
| R9 | 包体/性能 | 中 | Node 宿主 + 前端 + 技能 | 不背 Chromium；按需加载；技能外置 |
| R10 | 上架合规 | 中高 | 隐私、权限、商标、AI 内容 | 提前做 AGC 材料；不用 Google 商标 |
| R11 | 模型质量差距 | 中 | Antigravity harness 与 Gemini 协同调优 | 做 eval；工具 schema/prompt 迭代；接受差距 |
| R12 | 维护成本 | 中 | 系统/模型/技能持续变化 | 版本化；自动化测试；技能 lint |

---

## 9. 决策建议

### 9.1 按目标选路线

| 你的真实目标 | 选 |
|---|---|
| “我现在就要在鸿蒙 PC 上用 Antigravity” | **A（Remote Control）** |
| “我要一个鸿蒙原生的 agent 产品” | **B（原生重建）**，先 Gate 0 |
| “我要把 Antigravity 原样搬过来” | **停止**；技术 + 法律都不可行 |
| “我要团队共享/长任务/云端重活” | **D（混合远程）** |
| “我只是想验证 CLI 能不能跑” | E，但别当产品 |

### 9.2 本周可做的事

1. **A 路线**：找一台 Linux/macOS/Windows 主机装 Antigravity，开 Remote Control；鸿蒙浏览器登录同账号，跑一个真实任务，记录体验/延迟/限制。
2. **B 路线**：只做 G0-3（Node 宿主 + 模型 SSE + 文件工具 + Skills），2 天内出结果；不要先写 UI。
3. **法务**：把 Antigravity ToS 第 6 条、Gemini API 条款、AGC AI 应用规范拉齐，确认“不做第三方 Antigravity 客户端”的边界。
4. **不要做**：不要 clone Antigravity 的 asar 去改；不要把 `language_server` 打进 HAP；不要用 Google 商标做产品名。

### 9.3 一句话给决策层

> **Antigravity 的护城河不是 Electron UI，而是那个 203 MB 的 Go agent runtime 和 Google 的模型/云。前者鸿蒙跑不了，后者第三方不能用。所以“迁移 Antigravity”应翻译成“在鸿蒙上重建一个 Antigravity 级 agent”，而不是“把 Antigravity 搬过来”。**

---

## 10. 附录

### 10.1 关键证据

| 证据 | 位置 |
|---|---|
| Antigravity 2.33.0 包体实测 | [evidence-antigravity-package.md](evidence-antigravity-package.md) |
| `app.asar` 启动 LS / UI 由 LS 提供 | 本报告 §2.2；解包 JS `dist/main.js`、`dist/languageServer.js`、`dist/lsDefaults.js` |
| LS 的 glibc 依赖 | `readelf -d resources/bin/language_server` |
| 鸿蒙 exec/dlopen 硬约束 | `hmskills/harmonyos-porting/references/hard-constraints.md` |
| Electron V40 能力边界 | `hmskills/harmonyos-electron-porting/references/api-adapters.md`、`runtime-versions.md` |
| Node 进程内宿主路线 | `hmskills/harmonyos-node-inprocess-host/SKILL.md` |
| 本机 DSH Gate 0 真机数据 | `dsh-desktop-ohos/docs/gate0-device-probe.md` |
| Antigravity ToS 第 6 条 | <https://antigravity.google/terms> |
| Antigravity Remote Control | <https://antigravity.google/docs/remote-control> |
| Antigravity Skills 标准 | <https://antigravity.google/docs/skills> |
| Antigravity MCP | <https://antigravity.google/docs/mcp> |
| Antigravity 平台要求 | <https://antigravity.google/docs/getting-started> |

### 10.2 ToS 原文（第 6 条）

> You must not abuse, harm, interfere with, or disrupt the Service. This includes, but is not limited to, using the Service in connection with products not provided by us. Using third party software, tools, or services to access the Service (e.g. using OpenClaw with Antigravity OAuth) is a breach of this Agreement. Such actions may be grounds for suspension or termination of your Antigravity and/or Gemini CLI accounts.

### 10.3 术语

| 术语 | 含义 |
|---|---|
| LS | `language_server`，Antigravity 的本地 Go runtime，提供 UI + agent + 工具 |
| HAP | HarmonyOS Ability Package，鸿蒙应用安装包 |
| HNP | HarmonyOS Native Package/公共池，开发态可用的系统二进制目录 |
| exec | 应用进程 fork/exec 外部 ELF；鸿蒙应用态被禁 |
| dlopen | 动态加载 `.so`；鸿蒙只允许 HAP `libs/` 内的自签 `.so` |
| SKILL.md | Agent Skills 开放标准的技能清单文件 |
| MCP | Model Context Protocol，模型上下文协议 |
| Remote Control | Antigravity 官方远程控制：浏览器驱动桌面/CLI 会话 |

### 10.4 版本敏感性

- 本报告基于 Antigravity **2.33.0 / Electron 44.9.1**（2026-11-17 构建）。Google 更新后，包结构/二进制可能变化；结论（LS 是核心、glibc、禁 exec）预计不变，但具体版本号/大小需重测。
- 鸿蒙侧基于 Electron for OHOS **V40** 与本机 HarmonyOS 1.13.0；系统升级后 spawn/PTY/ArkWeb 行为可能变化，Gate 0 需在新系统上复跑。
- `hmskills` 的 139 个坑位有版本敏感性；引用时以仓库最新 `hard-constraints.md` 为准。
