# ohos-agy

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

Dependencies: `curl`, `tar`, `python3`, `/data/service/hnp/bin/binary-sign-tool` (the last two ship with HarmonyOS PC).

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
└── templates/
    ├── agy.launcher.sh
    └── zshrc.snippet
```

> Detailed docs are written in Chinese. If you need any of them in English, open an issue.

> The research cache (about 1.8 GB of official packages and extracted artifacts) is **not** committed. Reproduction steps are in the [evidence doc](docs/evidence-antigravity-package.md).

---

## Verified capabilities (against the nextPDF project)

- Code reading: correctly identified Hvigor + ohpm, the Stage model, the `entry` module and `EntryAbility`
- Command execution: `git status`, `ls`, build scripts
- Full build: `clean` 5.6s + `build` 18.1s (`CompileArkTS` 7.3s) → signed HAP produced

---

## Disclaimer

- `agy` is a **closed-source** Google binary (`github.com/google-antigravity/antigravity-cli` contains only a README and issue templates — no source, no LICENSE file).
- This project only performs **binary patching, self-signing and launcher setup**. It does not reimplement anything, does not alter functionality, and does not circumvent licensing.
- No Google binaries are distributed here; `install.sh` downloads them from Google's official release endpoint.
- Antigravity is a trademark of Google LLC. This project is not affiliated with Google; the name only identifies the ported target.
- Disabling the sandbox gives the agent full control over your filesystem. Evaluate the risk yourself; use it on your own machine only.
- Self-signing weakens system integrity guarantees; intended for development machines.

## License

Code and documentation: MIT, see [LICENSE](LICENSE) (© 2026 kehahn).
