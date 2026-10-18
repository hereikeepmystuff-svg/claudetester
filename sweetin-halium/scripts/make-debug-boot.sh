#!/bin/bash
# DEBUG ONLY: build a boot image that deliberately panics the kernel 45 s after the Halium initramfs starts,
# so the full kernel log is kept in pstore/ramoops RAM (CONFIG_PSTORE_CONSOLE/RAM, PANIC_TIMEOUT=5) and can be
# read after the reboot with: adb shell cat /sys/fs/pstore/console-ramoops-0   (from a recovery with adb).
# The device will reboot-loop on purpose. Flash a normal boot image to stop it.
# Usage: scripts/make-debug-boot.sh [stock-boot.img] [output.img]
#   With stock-boot.img its DTB blob is used (needs the matching stock dtbo); otherwise the port's own DTB.
set -euo pipefail
cd "$(dirname "$0")/.."
STOCK=${1:-}
OUT=${2:-boot-debug-pstore.img}
PORT=workdir/tmp/partitions/boot.img
T=workdir/downloads/android_system_tools_mkbootimg
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
python3 -I "$T/unpack_bootimg.py" --boot_img "$PORT" --out "$TMP/port" | tee "$TMP/port.txt" >/dev/null
DTB="$TMP/port/dtb"
if [ -n "$STOCK" ]; then
    python3 -I "$T/unpack_bootimg.py" --boot_img "$STOCK" --out "$TMP/stock" >/dev/null
    DTB="$TMP/stock/dtb"
fi
CMDLINE="$(sed -n 's/^command line args: //p' "$TMP/port.txt") ignore_loglevel"
mkdir "$TMP/rd" && (cd "$TMP/rd" && zcat "$TMP/port/ramdisk" | cpio -idm --no-absolute-filenames 2>/dev/null)
python3 -I - "$TMP/rd/init" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = 'mount -t proc -o nodev,noexec,nosuid proc /proc\n'
assert s.count(a) == 1
s = s.replace(a, a + '\n# ---- DEBUG (sweetin port): force a panic 45 s after init starts to keep the kernel log in pstore.\n'
              '( sleep 45; echo "sweetin-debug: forcing panic to preserve kernel log" > /dev/kmsg; echo c > /proc/sysrq-trigger ) &\n# ---- END DEBUG\n')
open(p, 'w').write(s)
PY
(cd "$TMP/rd" && find . | LC_ALL=C sort | cpio -H newc -o -R 0:0 2>/dev/null | gzip -9n > "$TMP/ramdisk-debug.gz")
PYTHONPATH="$T" python3 "$T/mkbootimg.py" --kernel "$TMP/port/kernel" --ramdisk "$TMP/ramdisk-debug.gz" --dtb "$DTB" \
    --dtb_offset 0x01f00000 --base 0x00000000 --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 \
    --second_offset 0x00000000 --tags_offset 0x00000100 --pagesize 4096 --header_version 2 \
    --os_version 11.0.0 --os_patch_level 2021-12 --cmdline "$CMDLINE" -o "$OUT"
ls -la "$OUT"
