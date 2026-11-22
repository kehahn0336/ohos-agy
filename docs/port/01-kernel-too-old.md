# 01 · 为什么 agy 报 `FATAL: kernel too old`

## 现象

```
$ ./agy --version
FATAL: kernel too old
$ echo $?
134
```

134 = 128 + 6，即 **SIGABRT**（不是 127，这点很关键）。

## 原因

agy 是静态链接的 aarch64 可执行文件，里面链了 glibc。启动路径：

```
ELF entry → glibc _start → __libc_start_main
           → bl _dl_discover_osversion      # 解析 uname(2) 的 release
           → lsr w8, w0, #8                 # 取主次版本
           → cmp w8, #0x306                 # 要求 >= 3.6
           → b.ls <fatal block>             # 不满足则跳去报错
```

鸿蒙的 `uname -r` 返回：

```
$ uname -r
HongMeng Kernel 1.13.0
```

glibc 逐段解析数字，得到 `1.13.0` → `0x010D00`，右移 8 位 = `0x010D`，远小于 `0x306`（3.6），于是判定“内核太老”。

`__libc_fatal()` 内部会 `abort()`，所以退出码是 134 而不是 127。

> 注意：`/proc/sys/kernel/osrelease` 也是同一串，改不了；静态链接下 `LD_PRELOAD` 无效。

## 反汇编证据

外层二进制里 `__libc_start_main` 的一段（地址随版本变化）：

```
5a1350:  bl   0x611640 <_dl_discover_osversion>
5a1354:  tbnz w0, #0x1f, 0x5a1498 <__libc_start_main+0x418>   ; 解析失败
...
5a1374:  lsr  w8, w0, #8
5a1378:  cmp  w8, #0x306
5a137c:  b.ls 0x5a14a4 <__libc_start_main+0x424>              ; 版本过低
...
5a1498:  adrp x0, 0x230000 ; add x0, x0, #0xe11 ; bl __libc_fatal
5a14a4:  adrp x0, 0x231000 ; add x0, x0, #0x445 ; bl __libc_fatal  ; "FATAL: kernel too old\n"
```

## 补丁

把两条跳向致命块的**条件分支**改成 NOP（`0xD503201F`），让执行继续往下走：

| 位置 | 原指令 | 含义 |
|---|---|---|
| `b.ls` | `0x54000949` | 版本 < 3.6 |
| `tbnz w0,#31` | `0x37f80a20` | 版本解析失败（返回负数） |

打完之后 `_dl_discover_osversion` 的返回值仍是 `0x010D00`，glibc 会据此关闭一些新特性（rseq 等），目前实测无副作用。

### 为什么要打两处

只打 `b.ls` 的话，一旦某台设备上解析彻底失败（返回负值），还会从 `tbnz` 那条路杀掉进程。两条都改才稳。

### 1.5.13 的具体偏移（仅供参考，脚本会自动定位）

| 所属 | vaddr | 文件偏移 |
|---|---|---|
| 外层 版本检查 | `0xafc0b7c` | `0xadc0b7c` |
| 外层 解析失败 | `0xafc0b54` | `0xadc0b54` |
| 内嵌 rg 版本检查 | `0x5a137c` | `0xbfe487f` |
| 内嵌 rg 解析失败 | `0x5a1354` | `0xbfe4857` |

## 一个容易踩的坑：字符串有两份

`FATAL: kernel too old` 在文件里出现**两次**：

1. 外层 ELF 的 `.rodata` —— **生效的那份**
2. `.noptrdata` 里内嵌的一个 9.37MB 静态 ELF（agy 自带的 ripgrep）的 `.rodata` —— 与启动无关

我第一版改的是内嵌那份，跑起来毫无变化。

**判定哪份生效的办法**：把字符串开头 5 字节改成 `PATCH`，看输出变不变。

```
probe_A（改外层）   → 输出 "PATCH: kernel too old"   ← 生效
probe_B（改内嵌）   → 输出 "FATAL: kernel too old"   ← 无关
```

## 自动定位逻辑（`scripts/repatch.py`）

不写死偏移，按语义找：

1. 搜二进制里所有 `FATAL: kernel too old` 出现位置 → 换算成 vaddr
2. 扫可执行段，找引用该 vaddr 的 `adrp` + `add` 指令对 → 拿到 `add` 的地址
3. 致命块起点 = `add` 前 4 字节（`adrp`）；兄弟块在 `add - 16`
4. 扫所有分支指令，跳到这两个起点的 → 改成 NOP
5. 对每个内嵌 ELF（magic 自洽的）重复 1-4

输出与手工补丁逐字节一致，换版本也能用。
