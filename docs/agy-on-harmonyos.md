# 在鸿蒙上使用 `agy`（Antigravity CLI）+ 自己的 Google 账号

> ⚠️ **本文档已过时（2026-11-20 晚修正）。**
> 下面的“鸿蒙本机直接运行不可行”结论已被推翻：使用 **`linux-arm64-musl` 静态构建** + 内核版本补丁 + 自签名 bash 后，`agy` 可以在鸿蒙本机直接跑起来，见 [port/](port/)。
> 本文保留，作为**“Linux 主机 + SSH”**这条备选路径的参考（不依赖任何补丁，但需要另一台机器）。

> 结论：**鸿蒙本机直接运行官方 `agy` 不可行；把 `agy` 放在一台 Linux 主机/云主机上，鸿蒙通过 SSH 使用，是可行且官方支持的路径。**  
> 官方 CLI 的 Remote SSH OAuth 流程就是为这种场景设计的：远程终端打印授权 URL，浏览器完成登录，回终端粘贴授权码。

---

## 0. 先说你最关心的

| 方案 | 能不能用自己账号 | 结论 |
|---|---|---|
| 鸿蒙本机直接 `./agy` | — | ❌ 不可行：`agy` 是 glibc 动态二进制，鸿蒙是 musl；自带 glibc loader 也在映射阶段被系统拒绝 |
| Linux 主机 + 鸿蒙 SSH 过去 | ✅ Google OAuth | ✅ **推荐**；官方支持 Remote SSH OAuth |
| Antigravity Remote Control 网页版 | ✅ Google OAuth | ✅ 最省事；但需要一台跑着 Antigravity App/CLI 的主机 |
| 鸿蒙上的 Linux 容器 | ✅ | ❌ 不解决问题：容器共享鸿蒙内核，glibc 一样跑不起来 |
| 鸿蒙上的 Linux VM | ✅ | ⚠ 理论可行；这台机器没有 `/dev/kvm`、没有 `qemu-system`，纯软件模拟会非常慢，不推荐 |

---

## 1. 为什么本机不行（实测，不是猜）

官方 Linux ARM64 CLI 包（1.1.28）：

```text
antigravity: ELF shared object, 64-bit LSB arm64,
             dynamic (/lib/ld-linux-aarch64.so.1), stripped
size:        200,364,264 B
Go:          go1.28-20260721-RC01
NEEDED:      libresolv.so.2, libpthread.so.0, libm.so.6,
             libdl.so.2, librt.so.1, libc.so.6
GLIBC:       2.17 / 2.18 / 2.25 / 2.26
```

鸿蒙只有：

```text
/lib/ld-musl-aarch64.so.1     ← musl
```

没有 `/lib/ld-linux-aarch64.so.1`，也没有 `libc.so.6`。  
我额外下载了 Debian arm64 的 `libc6`（glibc 2.41 和 2.28 两代），用 `ld-linux-aarch64.so.1 --library-path ...` 启动：

- loader 本身签名后能运行（`ld.so ... version 2.41`）；
- 但加载目标程序时统一报：

```text
error while loading shared libraries:
...: failed to map segment from shared object
```

连 Debian 自带的 `/bin/echo`（同样 glibc、已经用 `binary-sign-tool` 签名）也一样。  
换 glibc 2.28/2.41、换 `/storage`/`/tmp` 都一样。结论：**这不是缺某个 `.so`，而是这条 glibc 用户态加载路径在这台 HarmonyOS 上走不通**。继续在这上面耗没有意义。

> 注意：`agy` 是 Google 官方 CLI，不是“第三方客户端”。用你自己的账号跑官方 `agy` 不违反 ToS；违反 ToS 的是“用第三方软件/工具访问 Antigravity Service”。所以下面这条 SSH 路线是合规的。

---

## 2. 推荐方案：Linux 主机 + SSH

### 2.1 准备一台 Linux 主机

要求：

- Linux aarch64 或 x86_64；
- glibc ≥ 2.28（Ubuntu 20.04+ / Debian 10+ / Fedora 36+ / RHEL 8+）；
- 能访问 `antigravity.google` 与 Google 登录；
- 有 `~/.local/bin` 写权限；
- 最好有 Chrome 144+（只有你要用 `/browser` 子 agent 时才需要）。

可以是：公司/家里的 Linux 开发机、云主机、GitHub Codespaces、Google Cloud Shell 等。  
**不要用鸿蒙本机的容器**：容器共享内核，glibc 问题依旧。

### 2.2 在 Linux 主机上安装 `agy`

官方安装脚本：

```bash
curl -fsSL https://antigravity.google/cli/install.sh | bash
```

默认装到 `~/.local/bin/agy`。确认：

```bash
~/.local/bin/agy --version
```

如果 `antigravity.google` 访问不了，用 Google Cloud Storage 直链（以 1.1.28 为例；x64 换成 `linux-x64/cli_linux_x64.tar.gz`）：

```bash
mkdir -p ~/.local/bin /tmp/agy
curl -fL --retry 3 \
  'https://storage.googleapis.com/antigravity-public/antigravity-cli/1.1.28-5576113066475520/linux-arm/cli_linux_arm64.tar.gz' \
  -o /tmp/agy/cli.tar.gz
tar xzf /tmp/agy/cli.tar.gz -C /tmp/agy
install -m 755 /tmp/agy/antigravity ~/.local/bin/agy
```

### 2.3 从鸿蒙 SSH 过去

鸿蒙自带 OpenSSH：

```bash
ssh -t user@your-linux-host
```

登录后：

```bash
export PATH="$HOME/.local/bin:$PATH"
agy
```

> 用 `ssh -t` 分配 TTY；`agy` 的 TUI 需要 TTY。

### 2.4 登录（官方 Remote SSH OAuth 流程）

`agy` 检测到 SSH 环境后，不会尝试打开远程浏览器，而是：

1. 在终端打印一条 **授权 URL**；
2. 你在鸿蒙浏览器里打开这条 URL；
3. 用**你自己的 Google 账号**登录并授权；
4. 浏览器显示一个**字母数字授权码**；
5. 把授权码粘贴回 SSH 终端。

关键日志/行为：

```text
Using file-based token storage because SSH session detected
```

因为 SSH 环境没有 D-Bus/Secret Service，`agy` 会把 token 落到文件：

```text
~/.gemini/antigravity-cli/antigravity-oauth-token
```

而不是系统 keyring。这正是我们要的：重启后还能用。

> 如果你不是通过 SSH，而是在某个本地终端里跑（比如 Linux 桌面），可以手动强制 SSH 环境来走 URL + 文件存储：
>
> ```bash
> export SSH_CONNECTION="1 1 1 1"
> export SSH_CLIENT="1 1 1 1 1"
> export SSH_TTY=/dev/pts/0
> agy
> ```

### 2.5 文件在哪：远端，不是鸿蒙本地

`agy` 跑在 Linux 主机上，它看到的是**那台主机的文件系统**，不是鸿蒙 PC 的 `/storage/...`。  
所以：

- 项目在 Linux 主机上（clone/checkout 过去）：直接可用；
- 项目只在鸿蒙 PC 上：用 `git`/`rsync` 同步到主机，改完再同步回来；
- 需要“直接编辑鸿蒙本地目录”：SSH 方案不满足，得用 Linux VM + 共享目录，或走“原生重建”路线（成本高得多）。

### 2.6 验证登录与 headless 用法

登录完成后，在 TUI 里直接对话；或者退出 TUI 后用 headless：

```bash
agy -p "用一句话介绍这个仓库"
```

首次 headless 会复用刚才的 token；不需要再登录。

常用：

```bash
agy -p "修复这个测试失败" --dangerously-skip-permissions
agy --remote-control          # 开 Remote Control，浏览器接管
agy mcp add ...               # MCP（stdio 在 Linux 上可用）
```

`agy --help` 看全部参数；`/logout` 清 token。

---

## 3. 登录后的目录与配置

| 路径 | 作用 |
|---|---|
| `~/.gemini/antigravity-cli/antigravity-oauth-token` | SSH 模式下的 OAuth token（文件存储） |
| `~/.gemini/antigravity-cli/settings.json` | CLI 设置；可配 `modelProvider`、权限等 |
| `~/.gemini/antigravity-cli/` | 会话/缓存/日志 |
| `~/.local/bin/agy` | CLI 二进制 |

如果 token 文件权限过宽，建议：

```bash
chmod 700 ~/.gemini/antigravity-cli
chmod 600 ~/.gemini/antigravity-cli/antigravity-oauth-token
```

不要把 token 复制到仓库、聊天记录或 HAP 里。

---

## 4. 常见问题

### 4.1 `agy` 启动后又要登录 / token 不持久

说明它走了 keyring 且 keyring 不可用（D-Bus 缺失）。  
解决：确保通过 SSH 启动（`SSH_CONNECTION` 存在），或手动 export 上面三个变量；确认日志出现 `Using file-based token storage because SSH session detected`。

### 4.2 浏览器打开授权 URL 后没有授权码

- 确认登录的是你自己的 Google 账号；
- 确认没有拦截 `accounts.google.com`；
- 授权完成后页面会显示 code；复制完整 code，不要带空格；
- 如果页面一直转圈，换浏览器/网络再试。

### 4.3 `/browser` 不可用

`agy` 的 `/browser` 在 CLI 下需要 **Chrome 144+** 与 `npx`/Node。Linux 主机上装 Chrome 即可；不装就只能用非浏览器工具。鸿蒙本机没有 Chrome，所以这个子 agent 本来也不该在鸿蒙侧跑。

### 4.4 终端工具报错

`agy` 的终端工具在 Linux 主机上跑，用的是主机的 shell；正常。  
如果主机 shell 不是 `bash`，在 `settings.json` 或环境里指定；`agy` 的默认 shell 逻辑与平台有关。

### 4.5 网络/地区

`agy` 要连 Google 登录与 Cloud Code 后端；网络不可达时会在登录或模型请求处失败。这是网络问题，不是鸿蒙兼容问题。请确保主机侧网络可达，并遵守当地法规与 Google 条款。

---

## 5. 如果你没有 Linux 主机

按成本从低到高：

1. **Antigravity Remote Control**：找一台 macOS/Windows/Linux 桌面装 Antigravity App，开启 Remote Control；鸿蒙浏览器打开 `https://antigravity.google.com/`，同账号登录。零安装、零移植。
2. **云主机**：任意 Linux VM（arm64/x64 均可），按上面 §2 安装 `agy`，鸿蒙 SSH。
3. **GitHub Codespaces / Dev Container**：Linux 环境，SSH 进去装 `agy`；注意会话有效期与网络。
4. **鸿蒙本机 Linux VM**：这台机器没有 `/dev/kvm`，纯 TCG 模拟会非常慢；不建议作为日常方案。

---

## 6. 一句话

> **`agy` 本身没问题，问题是它要求 glibc Linux 用户态；鸿蒙给不了。把它放在 Linux 主机上，鸿蒙只做 SSH 终端/浏览器，账号仍然是你自己的，这是目前最稳、最合规的用法。**

---

## 附：本次实测命令（可复现）

```bash
# 1. 下载官方 CLI
curl -fL \
  'https://storage.googleapis.com/antigravity-public/antigravity-cli/1.1.28-5576113066475520/linux-arm/cli_linux_arm64.tar.gz' \
  -o /tmp/agy.tar.gz
tar xzf /tmp/agy.tar.gz -C /tmp
file /tmp/antigravity
readelf -d /tmp/antigravity | grep NEEDED

# 2. 自带 glibc（Debian arm64 libc6）并签名
#    （详细包地址见 .research/agy/；这里只列关键步骤）
binary-sign-tool sign -inFile .../ld-linux-aarch64.so.1 \
  -outFile .../ld.so.signed -selfSign 1
chmod 755 .../ld.so.signed
.../ld.so.signed --library-path .../lib/aarch64-linux-gnu /tmp/antigravity --version

# 结果：
#   ld.so 能打印版本；
#   加载 /tmp/antigravity 或 /bin/echo 均报
#   "failed to map segment from shared object"
```

结论：本机直接跑不可行；转 §2 的 Linux + SSH 方案。
