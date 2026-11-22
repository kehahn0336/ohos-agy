# Gate 0：Antigravity 类 agent 上鸿蒙的 2 周验证清单

> 目的：在投入 UI/产品化之前，用最小实验证明“鸿蒙上能不能跑一个可用的 coding agent”。  
> 原则：**不碰 Antigravity 二进制、不做 Electron 平移**；只验证“原生重建”路线的最小闭环。  
> 产出：每个实验一段日志/截图/数据 + 一页 Go/No-Go 结论。

## 0. 先钉死两个已完成的否决项

### G0-1 Antigravity `app.asar` 在鸿蒙 Electron 上能否启动

**状态**：已完成静态判定，无需真机也能得出结论。  
**结论**：不能。`main.js` 先 `spawn(language_server)`，拿到端口后才创建窗口；LS 起不来就 `Startup failed` 退出。  
**真机复现（可选，1 天）**：

1. 用 `dsh-desktop-ohos/harmony/electron144_ohos_hap` 的 V40 骨架；
2. 把 `app.asar` 解包到 `resfile/resources/app/`（或直接放 asar，若运行时支持）；
3. `devecocli build` + 安装；
4. 预期：`language_server binary not found` 或 60 秒超时 → 错误框 → 退出。

**记录**：报错原文、hilog、是否创建窗口。

### G0-2 `language_server` 能否在鸿蒙 shell 直接跑

**状态**：已实测（2026-11-20）。  
**结果**：

```text
$ resources/bin/language_server --stamp
bash: .../language_server: Permission denied
rc=126

$ file resources/bin/language_server
ELF shared object, 64-bit LSB arm64, dynamic (/lib/ld-linux-aarch64.so.1), stripped

$ ls -l /lib/ld-linux-aarch64.so.1
ls: cannot access '/lib/ld-linux-aarch64.so.1': No such file or directory

$ ls -l /lib/libc.so.6
ls: cannot access '/lib/libc.so.6': No such file or directory
```

**判定**：双重失败——① 未签名/未放行，shell 直接 `Permission denied`；② 即使签名，也没有 glibc loader（`/lib/ld-linux-aarch64.so.1`）和 `libc.so.6`。应用态更不可能。  
**结论**：LS 不可搬。后续实验不再围绕它。

---

## 1. G0-3：Node 进程内宿主 + 模型 + 文件 + 技能（核心）

**目标**：证明“鸿蒙 HAP 内可以跑一个最小的 agent loop”。

**做法**：

1. 按 `hmskills/harmonyos-node-inprocess-host` 搭 HAP：
   - `entry/libs/arm64-v8a/` 放 `libnode.so.*`、`libc++_shared.so`、第三方 `.so`；
   - `entry/src/main/cpp/` 写 Dlopen 胶水（`startHost`/`stopHost`/`runtimeVersion`）；
   - `resfile/` 放入口 JS、核心树、技能；
   - ArkTS 壳 + ArkWeb UI（或先只做 ArkUI 状态页）。
2. 最小 host：
   - `GET /health`；
   - `POST /chat`（SSE 流式）；
   - `POST /tools/read`、`/tools/write`、`/tools/list`；
   - `GET /skills`（列出 `SKILL.md` 的 name/description）、`POST /skills/activate`。
3. 模型：Gemini API（如可达）或 DeepSeek/Qwen；用 OpenAI 兼容/SSE 均可。
4. 技能：放 2 个 `hmskills` 技能（如 `harmonyos-porting`、`harmonyos-arkui-develop-skill`），验证“按 description 命中 → 读全文”。

**通过标准**：

- HAP 真机启动，`/health` 返回 200；
- 3 轮工具调用闭环：读文件 → 改文件 → 再读校验；
- SSE 首 token < 2s（网络正常时），完整回答 < 30s；
- 技能列表正确，命中后能读到全文；
- 崩溃/重启后不丢会话（至少 JSONL 持久化）。

**失败即 No-Go**：如果 Node 宿主在 HAP 内起不来（`ERR_DLOPEN_FAILED`、`--jitless` 导致依赖不可用、HTTP 源起不来），先解决运行时，不进入 UI。

**参考**：`harmonyos-node-inprocess-host/references/runtime.md`、`packaging.md`、`native-modules.md`、`http-origin-serving.md`。

---

## 2. G0-4：终端（PTY）

**目标**：证明 agent 能在鸿蒙上执行命令；这是 coding agent 的生死线。

**做法**：

1. 用 microsoft/node-pty 源码，按 `harmonyos-node-toolchain` 编译（`P-091` 三件套：平台包/loader/签名）；
2. 把 `.node` 放进 HAP `libs/arm64-v8a/`，签名；
3. Node host 内 `require('node-pty')`，`spawn('/system/bin/sh', ['-c', 'echo hi'])`；
4. 测试：`pwd`、`ls`、`echo`、`cat`；再测一个需要 TTY 的命令（如 `top -n 1`）；
5. 记录：能否创建 PTY、能否拿到 stdout/stderr、退出码、信号、超时/取消。

**通过标准**：

- PTY 能创建，`echo`/`ls` 有输出，退出码正确；
- 能杀掉长命令；
- 只能执行系统可信 shell 与 HAP 内允许的命令；**不尝试 exec 自带二进制**。

**失败时的退路**：

- 只读 agent（文件/搜索/解释），不做命令执行；
- 或混合远程：终端在 Linux worker 上跑。

**注意**：不要用 HNP 池的 `bash` 作为产品依赖；HNP 是开发态，不是应用态。应用态只应依赖系统 `/system/bin/sh` 或 HAP 内允许的组件。

---

## 3. G0-5：浏览器自动化（ArkWeb）

**目标**：证明 agent 能打开页面、点击/输入、截图、读控制台；对应 Antigravity 的 browser 子 agent。

**做法**：

1. ArkWeb 加载本地/远程页面；
2. 用 `runJavaScript` 注入脚本：查询 DOM、点击、填表单、读文本；
3. 用 `javaScriptProxy` 暴露宿主方法（截图、导航、读 console）；
4. 截图：`componentSnapshot` 或 ArkWeb 的截图能力；
5. 进阶：`hdc fport` 转发 ArkWeb DevTools socket，用 Node 的 CDP 客户端连接（若可用）。

**通过标准**：

- 能完成一次“打开页面 → 填表单 → 点击 → 断言文本/截图”；
- 能拿到 console error（至少通过注入 hook）；
- 页面登录态可保持（cookie/存储）；
- 不需要 Chrome，不需要 `npx`。

**失败时的退路**：

- 只做“读页面 + 截图”，不做交互；
- 或把浏览器子 agent 放到远程 worker。

---

## 4. G0-6：MCP + 技能生态

**目标**：证明鸿蒙 agent 能接外部工具，而不是封闭工具集。

**做法**：

1. 起一个远程 MCP server（Streamable HTTP；可先用本地 Node 起，再部署到公网/内网）；
2. Node host 实现 MCP 客户端：`initialize`、`tools/list`、`tools/call`；
3. 至少接 2 个工具：一个只读（如天气/搜索），一个写（如 issue 创建）；
4. 技能：`<workspace>/.agents/skills/` 放 3 个 `SKILL.md`，验证渐进式披露；
5. 记录：工具 schema 大小、调用延迟、错误处理。

**通过标准**：

- `tools/list` 正确、`tools/call` 成功；
- 模型能根据 description 选工具；
- 技能命中率可接受（人工 10 条 prompt 测试）；
- 不依赖 `spawn` 本地 MCP server。

**说明**：Antigravity 的 MCP 支持 `command`（stdio）和 `serverUrl`（HTTP）。鸿蒙上 **stdio 不可用**，只做 HTTP；本地 MCP 若要支持，改成进程内 JS MCP server（同一 Node host 里注册工具）。

---

## 5. G0-7：模型/合规/上架

**目标**：确认“能合法地把模型接进来，并能上架”。

**检查项**：

1. **Antigravity ToS**：不做第三方 Antigravity 客户端；不碰 Antigravity OAuth/Cloud Code 后端。
2. **Gemini API / Vertex**：条款、配额、数据使用、地区可用性；是否允许商业分发。
3. **国内模型**：DeepSeek/Qwen 等 API 的条款、内容安全、实名/备案要求。
4. **AGC**：AI 应用分类、隐私政策、权限说明、内容安全、算法备案（如适用）。
5. **商标**：产品名/图标不能用 Antigravity/Google 商标；文案避免“官方”“兼容”误导。
6. **数据**：代码/文件是否出境；是否用于训练；用户授权与删除。

**通过标准**：法务/合规给出书面结论；至少一条模型链路可商用。

**No-Go**：没有合法模型链路，或上架被明确否决。

---

## 6. 两周排期

| 天 | 实验 | 产出 |
|---|---|---|
| D1–D2 | G0-1/G0-2 复现 + 记录 | 报错原文、结论（已基本完成） |
| D3–D5 | G0-3 Node 宿主 + 模型 + 文件 + 技能 | 真机日志、SSE 延迟、技能命中 |
| D6–D8 | G0-4 PTY | PTY 日志、命令矩阵、失败模式 |
| D9–D10 | G0-5 ArkWeb 自动化 | 录屏/截图、脚本、CDP 可行性 |
| D11–D12 | G0-6 MCP + 技能 | 工具调用记录、延迟 |
| D13–D14 | G0-7 合规 + 汇总 | Go/No-Go 备忘录 |

## 7. Go / No-Go 判定

| 结果 | 条件 | 下一步 |
|---|---|---|
| **Go** | G0-3 通过；G0-4 或 G0-5 至少一个通过；G0-7 无否决 | 进入 MVP（8–10 周） |
| **Conditional Go** | G0-3 通过；G0-4 失败，但可接受“只读/远程终端” | 做只读 agent 或混合远程 |
| **No-Go** | G0-3 失败（Node 宿主起不来）；或 G0-7 明确否决 | 停止本地 agent；转 Remote Control/远程方案 |

## 8. 交付物清单

- `spike/node-host/`：最小 Node 宿主 HAP 工程；
- `spike/pty/`：PTY 测试；
- `spike/arkweb/`：ArkWeb 自动化测试；
- `spike/mcp/`：MCP 客户端；
- `docs/gate0-report.md`：数据、截图、结论；
- `docs/decision.md`：Go/No-Go 一页纸。

## 9. 不要做的事

- 不要把 Antigravity 的 `language_server`、`app.asar`、`antigravity` 二进制打进 HAP；
- 不要尝试“签名后 exec LS”作为产品方案；
- 不要用 Antigravity OAuth/Cloud Code 后端做第三方客户端；
- 不要先写 UI 再验证终端/模型；
- 不要把 HNP 池的 bash/node 当应用态依赖。
