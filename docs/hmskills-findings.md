# hmskills 中与 Antigravity 迁移直接相关的结论

> 来源：本地知识库 `hmskills`（16 个移植 skill、139 个坑位）与 `hmskills-cli`（40+ 个应用开发 skill），均为独立仓库，不在本工程内。  
> 这里只摘录会影响 Antigravity 判定的硬约束；完整内容以仓库为准。

## 1. 总入口：`harmonyos-porting`

三过滤（运行时能力 / 依赖链 / 形态）：

| 能力 | 结论 | 对 Antigravity 的影响 |
|---|---|---|
| 应用进程 `fork/exec` 自带 ELF | ❌ 三路全败（EACCES/EPERM） | LS 不能作为 HAP 的子进程启动 |
| `dlopen` HAP 内 `libs/arm64-v8a/*.so` | ✅ 唯一可靠通道 | 只能把自研原生库编进 HAP，不能加载 LS |
| `dlopen` 数据目录 `.so` | ❌ ENOENT | 不能运行时下载/解包原生库 |
| 运行时下载/热更新插件 | ❌ | 技能/插件必须随包或走远程 |
| `chmod` o 位 | ❌ 实际 0770 | 不能靠权限位让 ELF 可执行 |
| shell 态自签 ELF | ✅ | 只适合开发/调试，不是应用态 |

关键结论：**“shell 里能跑”不等于“应用里能跑”**。Antigravity LS 即使能在鸿蒙 shell 签名后运行，也不能进 HAP。

## 2. `harmonyos-electron-porting`

V40 运行时（Electron 40.1.0 / Chromium 144 / Node 24.11.1）：

- 仅 arm64-v8a；只适合 2in1/tablet；模拟器（x86_64）装不上；
- `child_process.spawn` / `fork` **无适配层**（P-049）；
- `utilityProcess.fork` 真机 `exit=5`，无 IPC；
- Node 原生 addon 需按华为文档重编并链 `libelectron.so`（P-051）；
- `@lydell/node-pty` 无 ohos 平台包（P-063）；
- `autoUpdater` 不支持，只能走应用市场（P-050）；
- `safeStorage` 半成品；
- 主进程日志不进 hilog，只有 `[WebEngine]` 适配器日志；
- 包体下限约 130 MB，运行时约 300 MB。

对应 Antigravity：**Electron 壳可以搬，但 `spawn(language_server)` 这一步必然失败；LS 不在，UI 也不在。**

## 3. `harmonyos-node-inprocess-host`

用 libnode + 进程内宿主替代 Electron：

- `libnode.so.*` 装 HAP `libs/`，Dlopen 胶水拉起；
- 不能 `exec`；所有 CLI 语义改成进程内实现 / 假 CLI 壳 + 队列 / 系统能力；
- `--jitless` 下 `WebAssembly` 不可用，依赖 WASM 的包要换；
- 原生 addon 要进 `libs/`、重定向、自签；
- 用宿主 HTTP 源替代 `resource://`，恢复 ESM/代码分割/SAB/Service Worker；
- 目录权限要运行时申请；picker 授权不跨重启（P-097）。

对应 Antigravity：**这是“重建 agent”最现实的底座**；但不能直接跑 Antigravity 的 LS，只能重写 agent loop/tools。

## 4. `harmonyos-arkweb-shell`

- 只适合零网络依赖的纯 Web 应用；
- 要发 HTTP 的应用会被 CORS 拦，必须 Electron-OH 主进程或宿主服务；
- `resource://` 下 ESM 不执行、Service Worker 注册失败、图片/canvas 有坑；
- 文件选择器需要 `onShowFileSelector` 桥接。

对应 Antigravity：**不能用 ArkWeb 包壳直接跑 Antigravity Web UI**（UI 由 LS 在 localhost 提供，且需要 Host Bridge/OAuth/本地文件能力）。

## 5. `harmonyos-node-toolchain`

- `process.platform === 'openharmony'`（Node 22+ 官方支持），npm 平台门控大量失效；
- node-pty 可源码编译（P-091 三件套），但需要平台包/loader/签名；
- pnpm 在 hmdfs 上不能硬链接（EPERM）；
- tsx 依赖 unix socket，沙箱禁用；
- 原生包要么用官方 openharmony 包，要么源码编译，要么 HNP 池（仅开发态）。

对应 Antigravity：终端、搜索、Git 这些“调外部 CLI”的工具，全部要改成进程内/原生库实现。

## 6. `harmonyos-hvigor-signing` / `harmonyos-toolchain`

- HAP 签名、`assembleApp`、`hap-sign-tool`；
- 本机 `getcwd` 可能坏，构建要显式传工程目录；
- hdc 部署、hilog、uitest dumpLayout；
- 无 DevEco 时可用 `signature generate` 一条龙。

对应 Antigravity：**重建路线的打包/上架可以复用这些 skill**；原样搬 LS 不适用。

## 7. 技能格式：与 Antigravity 兼容

Antigravity 的 Skills 是开放标准：

- `SKILL.md` + YAML frontmatter（`name`、`description`）；
- 渐进式披露：先看 name/description，命中后读全文；
- 目录：`<workspace>/.agents/skills/`、`~/.gemini/config/skills/`。

`hmskills` 的格式完全一致（`SKILL.md` + `references/` + 触发关键词）。因此：

- **技能库是唯一可以原样迁移的资产**；
- 重建路线可以直接把 16 个移植 skill / 40+ 个开发 skill 挂给鸿蒙 agent；
- 这也是最快能演示“鸿蒙 agent 懂鸿蒙”的部分。

## 8. 一句话

> `hmskills` 的结论不是“Antigravity 能不能移”，而是“**任何依赖外部 ELF 的架构都不能移**”。Antigravity 的 agent 恰好就是外部 ELF；所以只能重建。
