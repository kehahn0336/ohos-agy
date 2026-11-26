# ohos-agy

![license](assets/badges/license.svg) ![platform](assets/badges/platform.svg) ![agy](assets/badges/agy-version.svg)

[简体中文](README.md) | **English**

> **Unofficial port that makes Google Antigravity CLI (`agy`) run on HarmonyOS PC (aarch64).**
> It patches the glibc kernel-version check inside the static Linux build, self-signs the binary, and works around HarmonyOS's seccomp ban on namespace clones. Verified on HarmonyOS PC with agy 1.5.14 — chat, file I/O, shell commands and a full HAP build all work.
> Not affiliated with Google. Ships no Google binaries; `install.sh` downloads them from Google's own release endpoint.

> **Status: working.** Tested 2026-11-22 on HarmonyOS PC / aarch64 / HongMeng Kernel 1.13.0 with agy **1.5.14** (1.5.13 also verified).

```sh
cd ~/project/ohos-agy
bash scripts/install.sh
exec zsh
agy --version      # 1.5.14
```

---

## What this is — and what it is not

**It is** a recipe of **binary patches plus environment fixes**. `agy` ships for macOS / Windows / Linux / Googlebook only, and its installer gives up at `uname -s` returning `HarmonyOS`. The binary itself runs fine; three things block it, and all three can be worked around.

**It is not** a reimplementation, and it does not port the Antigravity App / IDE. The desktop product (Electron shell plus a 203 MB `language_server` dynamically linked against glibc) genuinely cannot be moved — see the [feasibility report](docs/antigravity-harmonyos-feasibility.md). That conclusion still holds; it just **does not apply to the CLI**.

> Correction: the earlier "agy cannot run locally" conclusion came from experiments on the **dynamically linked glibc build**, without the kernel-version patch. The `linux-arm64-musl` CLI build is **statically** linked and runs once glibc's startup check is patched out.

---

## The three blockers

| # | Blocker | Symptom | Fix |
|---|---|---|---|
| 1 | glibc kernel-version check | `FATAL: kernel too old`, exit code 134 (SIGABRT) | NOP two conditional branches → [01](docs/port/01-kernel-too-old.md) |
| 2 | Terminal sandbox uses namespaces | SIGSYS (rc=159) the moment a command runs; process killed | `--dangerously-skip-permissions` skips the sandbox → [02](docs/port/02-seccomp-namespace.md) |
| 3 | Default shell lives inside the HAP bundle | `fork/exec .../bundle/.../bash: permission denied` | Self-signed bash in `~/opt/bin`, prepended to PATH → [03](docs/port/03-bash-exec-denied.md) |

All three are required. Once installed:

```sh
$ agy -p "run echo hello"
Command exited with code 0.
Command output:
hello
```

---

## What it looks like

A real session (agy 1.5.14, HarmonyOS PC, nextPDF project) — not a mock-up:

```console
$ agy -p "build the app with assembleHap and tell me the result"

> ohpm install done (0s 120ms)
> hvigor Finished :entry:assembleHap... after 1 ms
> hvigor BUILD SUCCESSFUL in 3 s 244 ms
  33 tasks: 14 executed, 19 up-to-date

artifact: app/entry/build/default/outputs/default/entry-default-signed.hap (261 KB)
```

---

## Install

```sh
bash scripts/install.sh             # idempotent; skips download if already installed
bash scripts/check-update.sh        # check for a newer build only (touches nothing)
bash scripts/install.sh --force     # upgrade: download, patch, sign again
bash scripts/verify.sh              # five local self-checks
```

`install.sh` does the following:

1. Downloads the `linux_arm64_musl` build via its manifest and verifies SHA-512
2. Runs `scripts/repatch.py` to locate and NOP the kernel-version checks (no hard-coded offsets)
3. Self-signs with `binary-sign-tool -selfSign 1` (HarmonyOS requires a signature on every ELF)
4. Copies and signs a `bash` into `~/opt/bin/bash`
5. Generates the launcher `~/opt/bin/agy`
6. Appends the PATH entry to `~/.zshrc` (skipped if already present)

Dependencies: `curl`, `tar`, `python3`, `binary-sign-tool` (the last two ship with HarmonyOS PC).

### About binary-sign-tool

HarmonyOS requires every ELF to be signed. `install.sh` looks for the signer in this order:

```
~/command-line-tools/sdk/default/openharmony/toolchains/lib/binary-sign-tool   ← preferred
~/opt/bin/binary-sign-tool
/data/service/hnp/hmos-clt.org/*/sdk/default/openharmony/toolchains/lib/binary-sign-tool
/data/service/hnp/bin/binary-sign-tool
```

**The 2026-11-26 OTA removed the tool from the last path.** The first two are therefore preferred now. You can also point at it explicitly:

```sh
BINARY_SIGN_TOOL=/path/to/binary-sign-tool bash scripts/install.sh --force
```

Note: the copy under `/data/service/hnp` only runs because that directory is trusted — copying it elsewhere fails with `Operation not permitted`. The `command-line-tools` build is properly signed and can live in `~/opt/bin`. Both produce byte-identical signatures.

`check-update.sh` exit codes: `0` up to date, `10` newer version available, `2` query failed — safe to run from cron.

> ⚠️ Do **not** upgrade with `agy update`: it installs the official **unpatched, unsigned** binary and the CLI will not start afterwards. Upgrade only through `install.sh --force`.

---

## Costs and limitations

| Item | Status |
|---|---|
| Sandbox isolation | **Unavailable.** HarmonyOS kills the process with SIGSYS on `clone(CLONE_NEW*)`; there is no fallback path |
| Tool confirmation | **Fully auto-approved** (same switch controls both; you cannot keep confirmations and drop the sandbox) |
| Auto-update | **Must stay off** (the launcher sets `AGY_CLI_DISABLE_AUTO_UPDATE=1`). Otherwise the background updater replaces the binary with an unsigned one and the next start fails with `Permission denied` (126) |
| Platform detection | Not an issue. `agy` is a static Go binary; `GOOS=linux` is already correct |
| Network | Requires reachability of `*.googleapis.com`; occasional `EOF` on some networks, just retry |
| Architecture | aarch64 only (HarmonyOS PC / 2in1) |

---

## Layout

```
ohos-agy/
├── README.md                                  # Chinese (default)
├── README.en.md                               # this file
├── NOTICE.md                                  # third-party / trademark notices
├── docs/                                      # Chinese only
│   ├── port/                                  # how the port works (core)
│   │   ├── 01-kernel-too-old.md
│   │   ├── 02-seccomp-namespace.md
│   │   ├── 03-bash-exec-denied.md
│   │   └── 04-troubleshooting.md
│   ├── antigravity-harmonyos-feasibility.md   # feasibility study (App/IDE perspective)
│   ├── feasibility-summary.md                 # summary of the above
│   ├── evidence-antigravity-package.md        # evidence from the official package
│   ├── gate0-experiments.md                   # Gate 0 experiment list
│   ├── hmskills-findings.md                   # skill-format compatibility
│   └── agy-on-harmonyos.md                    # earlier approach: Linux host + SSH (historical)
├── scripts/
│   ├── install.sh
│   ├── check-update.sh
│   ├── verify.sh
│   ├── repatch.py            # locates patch points by string search
│   └── probe_seccomp.py      # enumerates syscalls blocked by seccomp
├── templates/
│   ├── agy.launcher.sh
│   └── zshrc.snippet
└── assets/badges/                             # local SVG badges (no shields.io)
```

> Detailed docs are written in Chinese. If you need any of them in English, open an issue.

> The research cache (about 1.8 GB of official packages and extracted artifacts) is **not** committed. Reproduction steps are in the [evidence doc](docs/evidence-antigravity-package.md).

---

## Version compatibility

`repatch.py` locates patch points by string search rather than fixed offsets, so new builds usually just work. Only combinations actually exercised are listed.

| agy version | Auto-located patch | Chat / file I/O | Shell commands | HAP build |
|---|---|---|---|---|
| **1.5.18** | ✅ | ✅ | ✅ | not re-tested |
| **1.5.14** | ✅ | ✅ | ✅ | not re-tested (commands verified) |
| **1.5.13** | ✅ | ✅ | ✅ | ✅ `clean` 5.6s + `build` 18.1s |
| others | expected | — | — | — |

Verified in detail (1.5.13 / nextPDF):

- Code reading: correctly identified Hvigor + ohpm, the Stage model, the `entry` module and `EntryAbility`
- Command execution: `git status`, `ls`, build scripts
- Full build: `CompileArkTS` 7.3s, 33 tasks with 32 executed → signed HAP produced

---

## FAQ

**Does it work on HarmonyOS phones / tablets?**
Untested. The sandbox restriction is the same as on PC, so it should in principle — but no device was tried. Don't treat it as a promise.

**Why must the sandbox be disabled?**
The HarmonyOS kernel replies to `clone(CLONE_NEW*)` with SIGSYS and kills the process. `agy`'s fallback logic never gets an error code to react to, so the sandbox has to be skipped entirely.

**Can Google ban my account for this?**
No. You use your own account, Google's own endpoints and the official CLI. Behaviour is identical to an unpatched install; only the binary is patched.

**Will an upgrade break it?**
Yes. Upgrading requires re-patching and re-signing. `check-update.sh` tells you when a new build exists; upgrade with `install.sh --force`, never with `agy update`.

**How does it differ from the official CLI?**
No sandbox isolation, no tool-call confirmation, no auto-update. Functionality is otherwise the same.

**Why not fork and maintain it yourself?**
`agy` is a closed-source binary — there is no source to fork. Binary patching is the only option.

---

## Disclaimer

- `agy` is a **closed-source** Google binary (`github.com/google-antigravity/antigravity-cli` contains only a README and issue templates — no source, no LICENSE file).
- This project only performs **binary patching, self-signing and launcher setup**. It does not reimplement anything, does not alter functionality, and does not circumvent licensing.
- No Google binaries are distributed here; `install.sh` downloads them from Google's official release endpoint.
- Antigravity is a trademark of Google LLC. This project is not affiliated with Google; the name only identifies the ported target.
- Disabling the sandbox gives the agent full control over your filesystem. Evaluate the risk yourself; use it on your own machine only.
- Self-signing weakens system integrity guarantees; intended for development machines.

## License

Code and documentation: MIT, see [LICENSE](LICENSE) (© 2026 kehahn). Third-party and trademark notices: [NOTICE](NOTICE.md).
