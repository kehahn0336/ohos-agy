#!/usr/bin/env python3
"""为 agy (Antigravity CLI) 的 aarch64 Linux 版打鸿蒙内核版本补丁。

原理：agy 静态链接的 glibc 在 __libc_start_main 里比对 uname release，
鸿蒙返回 "HongMeng Kernel 1.13.0" 被解析成 1.13 < 3.6，于是
__libc_fatal("FATAL: kernel too old") 并 abort。

做法：定位该字符串的 adrp+add 引用点，把跳进致命块的条件分支改成 NOP。
二进制里若嵌有其它静态 ELF（例如自带 ripgrep），一并处理。

用法：repatch.py <in> <out>
之后用 HarmonyOS 的 binary-sign-tool 自签名再执行：
  binary-sign-tool sign -inFile out -outFile out.signed -selfSign 1
"""
import struct
import sys

MSG = b"FATAL: kernel too old"
NOP = 0xD503201F


def load_sections(buf):
    shoff = struct.unpack_from("<Q", buf, 0x28)[0]
    shentsize = struct.unpack_from("<H", buf, 0x3A)[0]
    shnum = struct.unpack_from("<H", buf, 0x3C)[0]
    out = []
    for i in range(shnum):
        _, typ, flags, addr, off, size = struct.unpack_from(
            "<IIQQQQ", buf, shoff + i * shentsize)
        out.append((typ, flags, addr, off, size))
    return out


def sext(v, bits):
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


def find_strings(buf):
    res, i = [], 0
    while True:
        j = buf.find(MSG, i)
        if j < 0:
            return res
        res.append(j)
        i = j + 1


def find_add_sites(buf, vaddr, secs):
    """返回引用 vaddr 的 add 指令的 vaddr 列表。"""
    sites = []
    for typ, flags, addr, off, size in secs:
        if typ != 1 or not (flags & 4) or size < 16:
            continue
        blob = buf[off:off + size]
        n = len(blob) // 4
        words = struct.unpack("<%dI" % n, blob[:n * 4])
        reg = {}
        for i, w in enumerate(words):
            if (w & 0x9F000000) == 0x90000000:          # adrp
                imm = sext((((w >> 5) & 0x7FFFF) << 2) | ((w >> 29) & 3), 21) << 12
                reg[w & 0x1F] = ((addr + i * 4) & ~0xFFF) + imm
            elif (w & 0x7F000000) == 0x11000000:        # add (imm)
                rd, rn = w & 0x1F, (w >> 5) & 0x1F
                imm12 = (w >> 10) & 0xFFF
                sh = (w >> 22) & 1
                if rd == rn and rn in reg:
                    if reg[rn] + (imm12 << (12 if sh else 0)) == vaddr:
                        sites.append(addr + i * 4)
    return sites


def find_branches_to(buf, target, secs):
    hits = []
    for typ, flags, addr, off, size in secs:
        if typ != 1 or not (flags & 4) or size < 16:
            continue
        blob = buf[off:off + size]
        n = len(blob) // 4
        words = struct.unpack("<%dI" % n, blob[:n * 4])
        for i, w in enumerate(words):
            pc = addr + i * 4
            tgt = None
            if (w & 0xFC000000) == 0x14000000:
                tgt = pc + sext(w & 0x3FFFFFF, 26) * 4
            elif (w & 0xFF000010) == 0x54000000:
                tgt = pc + sext((w >> 5) & 0x7FFFF, 19) * 4
            elif (w & 0x7E000000) == 0x34000000:
                tgt = pc + sext((w >> 5) & 0x7FFFF, 19) * 4      # cbz/cbnz
            elif (w & 0x7E000000) == 0x36000000:
                tgt = pc + sext((w >> 5) & 0x3FFF, 14) * 4       # tbz/tbnz
            if tgt == target:
                hits.append(pc)
    return hits


def vaddr_to_off(vaddr, secs):
    for typ, flags, addr, off, size in secs:
        if typ == 1 and addr <= vaddr < addr + size:
            return off + (vaddr - addr)
    return None


def patch(buf, base, label):
    """buf: bytearray 副本；base: 该 ELF 在文件中的起始偏移（0 表示自身）"""
    secs = load_sections(buf[base:])
    patched = 0
    for soff in find_strings(buf[base:]):
        vaddr = None
        for typ, flags, addr, off, size in secs:
            if typ != 8 and off <= soff < off + size:   # 8 = SHT_NOBITS
                vaddr = addr + (soff - off)
                break
        if vaddr is None:
            continue
        for add_pc in find_add_sites(buf[base:], vaddr, secs):
            for block in (add_pc - 4, add_pc - 16):    # 致命块起于 adrp；兄弟块（另一条 FATAL）在其前
                for br in find_branches_to(buf[base:], block, secs):
                    foff = base + vaddr_to_off(br, secs)
                    if foff is None:
                        continue
                    struct.pack_into("<I", buf, foff, NOP)
                    print("  %s: nop branch @0x%x (file 0x%x)" % (label, br, foff))
                    patched += 1
    return patched


def main():
    src, dst = sys.argv[1], sys.argv[2]
    buf = bytearray(open(src, "rb").read())
    total = patch(buf, 0, "outer")
    # 处理内嵌 ELF（magic 出现在非 0 偏移处，且头部自洽）
    i = 4
    while True:
        j = buf.find(b"\x7fELF", i)
        if j < 0:
            break
        i = j + 4
        if j + 64 > len(buf):
            continue
        et, em = struct.unpack_from("<HH", buf, j + 16)
        if et != 2 or em != 183:
            continue
        try:
            total += patch(buf, j, "embedded@0x%x" % j)
        except Exception as e:                      # noqa: BLE001
            print("  skip embedded@0x%x: %s" % (j, e))
    open(dst, "wb").write(buf)
    print("patched %d branch(es) -> %s" % (total, dst))


main()
