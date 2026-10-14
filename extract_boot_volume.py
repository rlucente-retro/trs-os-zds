#!/usr/bin/env python3
import os
import sys

src = sys.argv[1] if len(sys.argv) > 1 else "TRS-OS_Squirrel.bin"
dst = sys.argv[2] if len(sys.argv) > 2 else "TRSDOS_7/boot_volume.dsk"

os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)

with open(src, "rb") as f:
    f.seek(66048)  # Seek past 0x010200 (64 KB kernel + 512 B slice tables)
    disk_data = f.read(425472)  # 425,472 bytes (Volume 0 DiskDISK boot image)

if len(disk_data) != 425472 or not disk_data.startswith(b"DiskDISK"):
    sys.exit(f"Error: Invalid boot volume data in {src} (len={len(disk_data)}, magic={disk_data[:8]})")

with open(dst, "wb") as f:
    f.write(disk_data)
