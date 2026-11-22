# ohos-agy · Google Antigravity 迁移 HarmonyOS 可行性（摘要）

> ⚠️ **CLI 部分结论已更新（2026-11-20 晚）。**
> 文中“本机直接跑 `agy` ❌”是基于 **glibc 动态构建**且未打内核版本补丁的实验。
> 改用 `linux-arm64-musl`（静态）构建 + 补丁 + 自签名 bash 后，`agy` 已在鸿蒙本机跑通，见 [port/](port/) 与仓库根 [README](../README.md)。
> **App / IDE 不可迁移的结论不变。**

> 评估日期：2026-11-20  
> 结论先行：**Antigravity 本体不能原样迁移；agent 能力可以重建；只在鸿蒙上“用”它，走官方 Remote Control 网页版。**
>
> **如果你只想跑 `agy`：本机直接跑 ❌（glibc 动态二进制，鸿蒙 loader 映射失败）；把 `agy` 放 Linux 主机、鸿蒙 SSH 过去 ✅。详见 [agy 运行手册](agy-on-harmonyos.md)。**

## 一句话结论

Antigravity 不是“一个 Electron 应用”，而是 **一个 Electron 外壳 + 一个 203 MB 的 Go `language_server`**。界面、agent、终端、文件、浏览器、MCP、技能全部由这个 `language_server` 提供；它动态链接 glibc，而鸿蒙应用进程既不能 `exec` 自带 ELF，也没有 glibc。**壳可以搬，脑子搬不了。**

## 六种“迁移/使用”的判定

| 目标 | 判定 | 说明 |
|---|---|---|
| 把 Antigravity App / IDE 原样搬到鸿蒙 | ❌ 不可行 | 核心 `language_server` 是 glibc Go 二进制，鸿蒙无法执行；没有它连界面都起不来 |
| 在鸿蒙本机直接跑 `agy` | ❌ 不可行 | 官方 `agy` 是 192 MB、动态链接 glibc 的二进制；鸿蒙无 glibc，自带 loader 也映射失败（实测） |
| Linux 主机 + 鸿蒙 SSH 跑 `agy` | ✅ 可行 | 官方 Remote SSH OAuth；用你自己的 Google 账号；鸿蒙只做终端/浏览器 |
| 在鸿蒙上重建“Antigravity 类” agent | ✅ 可行 | agent loop、工具层、UI 可自研；Node 进程内宿主 / ArkTS / ArkWeb 都有现成路径 |
| 在鸿蒙上直接使用 Antigravity | ✅ 可行（远程） | 官方 Remote Control：任意浏览器驱动另一台机器上的桌面/CLI 会话 |
| 迁移 Antigravity 技能（`SKILL.md`） | ✅ 直接可用 | 开放标准；`hmskills` 就是同格式的鸿蒙技能库 |

## 关键数字（实测）

| 项 | 值 |
|---|---|
| Antigravity App | 2.33.0（2026-11-17 构建） |
| Electron | 44.9.1 |
| `app.asar` | **6.47 MB**，1156 个文件，无 `.node` / `.wasm` |
| `resources/bin/language_server` | **203 MB**，Go 1.28，动态链接 glibc（`/lib/ld-linux-aarch64.so.1`） |
| UI 来源 | `https://127.0.0.1:<language_server 端口>/`（窗口在 LS 启动成功后才创建） |
| 鸿蒙侧运行时 | Electron for OHOS V40：Electron 40.1.0 / Chromium 144 / Node 24.11.1，仅 arm64、2in1/tablet |
| hmskills | 16 个移植 skill、139 个坑位；hmskills-cli 40+ 个应用开发 skill |

## 推荐动作

1. **想马上用**：在 Linux/macOS/Windows 主机上开 Antigravity 的 Remote Control，鸿蒙浏览器打开 `antigravity.google.com`，同账号登录即可。零移植。
2. **想做鸿蒙原生 agent**：不要从 Electron 平移开始；先做 2 周 Gate 0（模型 SSE、文件工具、PTY、ArkWeb 自动化、技能加载），再决定投入。
3. **想搬 Antigravity 代码**：停止。不是工作量问题，是 `language_server` 不可执行 + Google ToS 第 6 条禁止第三方客户端。

## 文档

- [完整可行性报告](antigravity-harmonyos-feasibility.md)
- [Antigravity 2.33.0 ARM64 包体实测证据](evidence-antigravity-package.md)
- [Gate 0 实验清单与 Go/No-Go](gate0-experiments.md)
- [hmskills 中与 Antigravity 直接相关的结论](hmskills-findings.md)
- [agy 运行手册：Linux 主机 + 鸿蒙 SSH](agy-on-harmonyos.md)

## 研究缓存

实测用的官方 Linux ARM64 包与解包产物在 `.research/antigravity/`（约 700 MB，可删）：

- `Antigravity-linux-arm.tar.gz`（203,199,363 B，SHA-256 `fb321bd9832403cf766e3e9719c2063cee1747a320925d3aecd4f0ce67ca6013`）
- `pkg/extracted/Antigravity-arm64/`（Electron 44.9.1 + `language_server`）
- `pkg/asar_extract_dist_*.js`（关键启动/拉起 LS 的代码）

> 这些是 Google 的二进制与代码，只用于本地可行性分析，**不要分发、不要入库、不要随 HAP 打包**。
