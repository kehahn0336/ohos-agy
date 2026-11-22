# Antigravity 2.33.0 ARM64 包体实测证据

> 目的：证明“Antigravity 的 agent 不在 Electron 里，而在 `language_server` 里；LS 是 glibc 二进制，鸿蒙应用态无法执行”。  
> 样本：官方 Linux ARM64 包，下载自 `storage.googleapis.com/antigravity-public/antigravity-hub/2.33.0-4731201358004224/linux-arm/Antigravity.tar.gz`。  
> 日期：2026-11-20。

## 1. 下载与校验

```text
URL:    https://storage.googleapis.com/antigravity-public/antigravity-hub/2.33.0-4731201358004224/linux-arm/Antigravity.tar.gz
Size:   203,199,363 bytes
SHA256: fb321bd9832403cf766e3e9719c2063cee1747a320925d3aecd4f0ce67ca6013
```

解包后顶层：

```text
Antigravity-arm64/
├── antigravity                        220,925,320 B   Electron 44.9.1
├── chrome-sandbox
├── chrome_crashpad_handler
├── libffmpeg.so
├── libvk_swiftshader.so
├── libvulkan.so.1
├── resources.pak
├── snapshot_blob.bin
├── v8_context_snapshot.bin
├── version                            44.9.1
├── locales/
└── resources/
    ├── app.asar                       6,473,373 B
    ├── app.asar.unpacked/            17 MB（仅 chrome-devtools-mcp）
    ├── bin/
    │   └── language_server            212,030,128 B
    ├── app-update.yml
    └── default_app.asar
```

## 2. 二进制判定

### 2.1 `file`

```text
antigravity:                            ELF shared object, 64-bit LSB arm64,
                                        dynamic (/lib/ld-linux-aarch64.so.1),
                                        BuildID=b7a5640d7f448fc6decb88689c8ac36bcee8ab45,
                                        stripped

resources/bin/language_server:          ELF shared object, 64-bit LSB arm64,
                                        dynamic (/lib/ld-linux-aarch64.so.1),
                                        BuildID=8822fc6748316f9117f0c0907afe10d9,
                                        stripped

chrome-sandbox:                         ELF shared object, 64-bit LSB arm64,
                                        dynamic (/lib/ld-linux-aarch64.so.1),
                                        stripped
```

### 2.2 `language_server` 的动态依赖

```text
$ readelf -d resources/bin/language_server

Dynamic section at offset 0x8799fa0 contains 34 entries:
  (NEEDED)  Shared library: [libresolv.so.2]
  (NEEDED)  Shared library: [libpthread.so.0]
  (NEEDED)  Shared library: [libm.so.6]
  (NEEDED)  Shared library: [libdl.so.2]
  (NEEDED)  Shared library: [librt.so.1]
  (NEEDED)  Shared library: [libc.so.6]
  (FLAGS)   BIND_NOW
  (FLAGS_1) Flags: NOW PIE
```

解释器：

```text
$ readelf -l resources/bin/language_server | grep interp
      [Requesting program interpreter: /lib/ld-linux-aarch64.so.1]
```

Go 版本与 glibc 符号：

```text
$ strings -n 8 resources/bin/language_server | grep -m1 '^go1'
go1.28-20261102-RC00 cl/1012564305 +298f53e483 X:fieldtrack,boringcrypto,simd,nogolistexportnewformat

$ strings -n 8 resources/bin/language_server | grep -m8 -E 'GLIBC_[0-9]|ld-linux|libc\.so'
GLIBC_2.17
libc.so.6
GLIBC_2.18
GLIBC_2.25
GLIBC_2.26
/usr/grte/v5/lib/ld-linux-aarch64.so.1
```

**判定**：这是 glibc 动态链接的 Linux ARM64 程序，不是鸿蒙 musl 程序。鸿蒙没有 `/lib/ld-linux-aarch64.so.1`，也没有 `libc.so.6`；应用态还禁止 `exec`。**双重不可执行。**

## 3. `app.asar` 解析

用 Python 解析 asar header（16 字节头 + JSON 目录）：

```text
first16: (4, 306308, 306304, 306300)
JSON:    data[16:16+306300]
base:    8 + 306308 = 306316
```

统计：

| 项 | 值 |
|---|---:|
| 文件数 | 1156 |
| 解压后总大小 | 20,437,427 B（约 20.4 MB） |
| `dist/` 文件 | 165 |
| `node_modules/` 包 | 20 |
| `.node` | 0 |
| `.wasm` | 0 |
| `app.asar.unpacked` | 17 MB，仅 `chrome-devtools-mcp` |
| 压缩后 asar | 6,473,373 B |

根 `package.json`：

```json
{
  "name": "antigravity",
  "productName": "Antigravity",
  "version": "2.33.0",
  "description": "Antigravity - Agentic Desktop Application",
  "homepage": "https://antigravity.google",
  "author": { "name": "Google", "email": "antigravity-support@google.com" },
  "main": "dist/main.js",
  "dependencies": {
    "@bufbuild/protobuf": "^2.11.0",
    "@connectrpc/connect": "^2.1.2",
    "@connectrpc/connect-node": "^2.2.0",
    "chrome-devtools-mcp": "^1.12.0",
    "electron-log": "^5.4.3",
    "electron-updater": "^6.8.9",
    "js-yaml": "^4.3.2"
  }
}
```

**没有原生模块、没有 ripgrep、没有 node-pty、没有浏览器引擎。** Electron 侧的职责只有窗口/菜单/托盘/SSH/更新/Host Bridge。

## 4. 启动链路：UI 由 LS 提供

### 4.1 `dist/main.js`

```js
// :519-556
handle = await startAndMonitorLanguageServer(targetPort, csrf, { ... });
...
catch (err) {
  await dialog.showErrorBox('Startup failed', err.message);
  app.quit();
  return;
}

// :563
const url = `${WINDOW_ORIGIN}:${handle.port}/`;

// :592-595
// Initial window — opened once after the LS has successfully started.
if (!HEADLESS) {
  setupApplicationMenu(url);
  createWindow(url, storageManager);
}
```

`dist/constants.js`：

```js
exports.DYNAMIC_PORT = 0;
exports.WINDOW_ORIGIN = 'https://127.0.0.1';
```

**解释**：Electron 先拉起 LS，拿到 LS 报告的端口，再打开 `https://127.0.0.1:<port>/`。**UI 是 LS 提供的 Web 页面**；LS 起不来，窗口不会创建。

### 4.2 `dist/languageServer.js`

```js
// :52
const child_process_1 = require("child_process");

// :83-87
const binName = isWindows ? 'language_server.exe' : 'language_server';
exports.LS_BINARY = app.isPackaged
  ? path.join(process.resourcesPath, 'bin', binName)
  : process.env.CODEIUM_LANGUAGE_SERVER_BIN || path.join(__dirname, '..', 'bin', binName);

// :273
_lsProcess = spawn(spawnCmd, spawnArgs, {
  stdio: ['pipe', 'pipe', 'pipe'],
  env,
});
```

启动超时：

```js
const LS_STARTUP_TIMEOUT_MS = 60000;
// ...
reject(new Error(`Timeout: language server did not report its port within ${LS_STARTUP_TIMEOUT_MS / 1000}s`));
```

### 4.3 `dist/lsDefaults.js`

```js
exports.LS_API_SERVER_URL = 'https://generativelanguage.googleapis.com';
exports.LS_CLOUD_CODE_ENDPOINT = 'https://daily-cloudcode-pa.googleapis.com';

function baseLsArgs(opts) {
  return [
    '--standalone',
    '--override_ide_name', 'antigravity',
    '--subclient_type', 'hub',
    '--override_ide_version', opts.ideVersion,
    '--override_user_agent_name', 'antigravity',
    '--https_server_port', String(opts.httpsServerPort),
    '--csrf_token', opts.csrfToken,
    '--app_data_dir', opts.appDataDir,
    '--api_server_url', exports.LS_API_SERVER_URL,
    '--cloud_code_endpoint', exports.LS_CLOUD_CODE_ENDPOINT,
  ];
}
```

### 4.4 数据目录

```js
function getAppDataDir() {
  return path.join(os.homedir(), '.gemini', getAppDataDirName());
}
```

`getAppDataDirName()` 在生产态为 `app.getName().toLowerCase().replace(/\s+/g, '')`，即 `antigravity`。

## 5. `language_server` 的职责（strings 证据）

`strings` 显示 LS 包含（节选）：

| 关键词 / 路径 | 含义 |
|---|---|
| `google3/third_party/jetski/...` | JetSki/Cortex：agent、轨迹、rehydration、工具调用 |
| `google3/google/internal/cloud/code/v1internal/...` | Google Cloud Code 后端协议 |
| `cloud_code_endpoint` / `cloudcode` | 连接 `daily-cloudcode-pa.googleapis.com` |
| `SKILL.md` / `skills` / `plugin` / `marketplace` | 技能、插件、市场 |
| `mcp_config.json` / `mcp server` / `streamable` | MCP 客户端 |
| `search_ripgrep.go` / `ANTIGRAVITY_DISABLE_EMBEDDED_RIPGREP` | 文件搜索 |
| `MOCK PTY` / `terminal` / `terminal shell` | 终端/PTY |
| `browser_tools` / `chrome-devtools-mcp` / `page.screenshot` | 浏览器子 agent |
| `worktree` / `git` / `checkout` / `commit` | Git/worktree |
| `sidecar` / `enable_sidecars` | 子进程 sidecar |
| `computer use` / `desktop actuator` | 桌面自动化 |
| `accounts.google.com` / OAuth | Google 登录 |
| `gemini-4-*` / `claude-*` | 模型清单 |

**结论**：LS 是 UI 服务 + agent runtime + 工具执行器 + 云端协议客户端 + 浏览器自动化 + MCP + 技能 + Git/终端。Electron 侧不实现这些。

## 6. 更新与运行时

`resources/app-update.yml`：

```yaml
provider: generic
url: https://antigravity-hub-auto-updater-974169037036.us-central1.run.app/manifest/
updaterCacheDirName: antigravity-updater
```

- 更新由 `electron-updater` 负责；鸿蒙没有 `autoUpdater` 适配，只能走应用市场。
- Electron 44.9.1 vs 鸿蒙运行时 40.1.0：差 4 个大版本；V40 的 Chromium 144 与 Electron 44 的 Chromium 版本接近，但 Electron 主进程 API 面有用量差异。

## 7. 与鸿蒙硬约束的对照

| 需求 | Antigravity 实际 | 鸿蒙应用态 | 结果 |
|---|---|---|---|
| 启动 LS | `child_process.spawn(LS_BINARY)` | `spawn` 无适配/静默挂死 | ❌ |
| LS 可执行 | glibc ELF，`/lib/ld-linux-aarch64.so.1` | musl，无 glibc loader；禁 exec 自带 ELF | ❌ |
| UI | LS 在 `https://127.0.0.1:<port>/` 提供 | 无 LS 则无 UI | ❌ |
| 终端 | LS 内 PTY | 只能系统 shell；不能 exec 自带二进制 | ⚠ |
| 搜索 | 内嵌/调用 ripgrep | 不能 exec `rg` | ⚠ |
| Git | `git`/worktree | 不能 exec `git` | ⚠ |
| MCP stdio | `spawn(command)` | 不能 spawn | ❌ |
| MCP HTTP | 网络 | 可用 | ✅ |
| Skills | 文件 + prompt | 可用 | ✅ |
| 更新 | electron-updater | 无 autoUpdater | ❌ |
| 法律 | Google ToS 第 6 条 | 第三方客户端违约 | ❌ |

## 8. 复现命令

> 研究缓存（下载包与解包产物，约 1.8 GB）**不入库**。复现时自己指定一个仓库外的目录，例如 `$HOME/.cache/ohos-agy-research`。
> 在 HarmonyOS 主机上，`getcwd` 可能失效；以下命令全部用绝对路径，避免 `cd`。

```bash
BASE=$HOME/.cache/ohos-agy-research/antigravity
mkdir -p "$BASE/pkg"
curl -L --max-time 1200 \
  'https://storage.googleapis.com/antigravity-public/antigravity-hub/2.33.0-4731201358004224/linux-arm/Antigravity.tar.gz' \
  -o "$BASE/pkg/Antigravity-linux-arm.tar.gz"

sha256sum "$BASE/pkg/Antigravity-linux-arm.tar.gz"

mkdir -p "$BASE/pkg/extracted"
tar xzf "$BASE/pkg/Antigravity-linux-arm.tar.gz" -C "$BASE/pkg/extracted"

file "$BASE/pkg/extracted/Antigravity-arm64/antigravity" \
     "$BASE/pkg/extracted/Antigravity-arm64/resources/bin/language_server"

readelf -d "$BASE/pkg/extracted/Antigravity-arm64/resources/bin/language_server" | head -30

strings -n 8 "$BASE/pkg/extracted/Antigravity-arm64/resources/bin/language_server" \
  | grep -m1 '^go1'
```

## 9. 边界与免责声明

- 本文只做**本地可行性分析**，不构成对 Google 代码/二进制的再分发许可。
- Antigravity 是 Google 的闭源产品；`language_server` 无源码，无法审计、无法重编、无法改造成 HAP `.so`。
- 包体版本/大小/内部路径会随 Google 更新变化；结论（LS 为核心、glibc、禁 exec）不随小版本改变，但复现时请以实际包为准。
- 不要把本文的二进制、asar 或反编译代码提交到公开仓库或打进 HAP。
