#!/usr/bin/env python3
"""快速枚举本机 seccomp 白名单外的系统调用号（fork 探测，不 exec）。"""
import ctypes
import os
import signal
import sys

libc = ctypes.CDLL("libc.so", use_errno=True)
blocked = []
for nr in range(0, 461):
    pid = os.fork()
    if pid == 0:
        signal.alarm(2)
        try:
            libc.syscall(nr, 0, 0, 0, 0, 0, 0)
        finally:
            os._exit(0)
    _, status = os.waitpid(pid, 0)
    if os.WIFSIGNALED(status) and os.WTERMSIG(status) == signal.SIGSYS:
        blocked.append(nr)
print("BLOCKED:", blocked)
