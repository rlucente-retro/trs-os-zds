#!/usr/bin/env python3
import os
import sys

src = sys.argv[1] if len(sys.argv) > 1 else "TRS-OS_Squirrel.bin"
dst = sys.argv[2] if len(sys.argv) > 2 else "TRSDOS_7/kernel.bin"

os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)

with open(src, "rb") as f:
    disk_data = f.read(66048)

if len(disk_data) != 66048:
    sys.exit(f"Error: Invalid kernel data in {src} (len={len(disk_data)})")

with open(dst, "wb") as f:
    f.write(disk_data)
