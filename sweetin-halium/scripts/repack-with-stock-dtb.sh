#!/bin/bash
# Experiment: swap the DTB in this port's boot.img for the one from your phone's STOCK boot.img.
# Rationale: the LineageOS 21 tree's reserved-memory map differs from stock Android 11 firmware
# (e.g. pil_adsp_region 0x1e00000 vs stock 0x2600000), which can reset the phone at the logo.
# Usage: scripts/repack-with-stock-dtb.sh stock-boot.img [port-boot.img] [output.img]
# Needs: ./build.sh already run (it clones AOSP's mkbootimg/unpack_bootimg into workdir/).
set -euo pipefail
cd "$(dirname "$0")/.."
STOCK=${1:?usage: $0 stock-boot.img [port-boot.img] [output.img]}
PORT=${2:-workdir/tmp/partitions/boot.img}
OUT=${3:-boot-sweetin-stockdtb.img}
T=workdir/downloads/android_system_tools_mkbootimg
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
python3 -I "$T/unpack_bootimg.py" --boot_img "$STOCK" --out "$TMP/stock" >/dev/null
python3 -I "$T/unpack_bootimg.py" --boot_img "$PORT" --out "$TMP/port" | tee "$TMP/port.txt" >/dev/null
CMDLINE=$(sed -n 's/^command line args: //p' "$TMP/port.txt")
PYTHONPATH="$T" python3 "$T/mkbootimg.py" \
    --kernel "$TMP/port/kernel" --ramdisk "$TMP/port/ramdisk" --dtb "$TMP/stock/dtb" \
    --dtb_offset 0x01f00000 --base 0x00000000 --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 \
    --second_offset 0x00000000 --tags_offset 0x00000100 --pagesize 4096 --header_version 2 \
    --os_version 11.0.0 --os_patch_level 2021-12 --cmdline "$CMDLINE" -o "$OUT"
ls -la "$OUT"
