#!/bin/bash
# Port-level wrapper around halium-generic-adaptation-build-tools.
# Clones the kernel and toolchains, applies patches/<set>/ and config/ fragments, then runs the generic build.
# Usage: ./build.sh [args passed to the generic build.sh, e.g. -k for kernel only]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
TOOLS="${TOOLS:-$HERE/build}"
BUILD_DIR="${BUILD_DIR:-$HERE/workdir}"
TOOLS_URL=https://gitlab.com/ubports/porting/community-ports/halium-generic-adaptation-build-tools

[ -d "$TOOLS" ] || git clone --depth 1 "$TOOLS_URL" "$TOOLS"

# mkdtboimg.py still invokes python2; fall back to python3 when python2 is not installed
if ! command -v python2 >/dev/null; then
    mkdir -p "$HERE/.shims"
    ln -sf "$(command -v python3)" "$HERE/.shims/python2"
    export PATH="$HERE/.shims:$PATH"
fi

source "$HERE/deviceinfo"
KERNEL_DIR="$BUILD_DIR/downloads/$(basename "${deviceinfo_kernel_source%.git}")"

# Qualcomm overlay sources need an overlay-aware dtc ("dtc_ext", see deviceinfo_kernel_use_dtc_ext). The tools download a
# 2017 LineageOS prebuilt for it; a blocked or failed download used to leave an HTML/JSON error saved as that "binary".
# Use the host's dtc (>= 1.5, supports /plugin/) instead, which the tools then skip downloading.
mkdir -p "$BUILD_DIR/downloads"
if [ ! -x "$BUILD_DIR/downloads/dtc_ext" ] || ! "$BUILD_DIR/downloads/dtc_ext" --version >/dev/null 2>&1; then
    command -v dtc >/dev/null || { echo "install device-tree-compiler (dtc >= 1.5)" >&2; exit 1; }
    cp -f "$(command -v dtc)" "$BUILD_DIR/downloads/dtc_ext"
fi

# 1. clone kernel + toolchains only
"$TOOLS/build.sh" -c -b "$BUILD_DIR" -o "$HERE/out"

# 2. patch the kernel and add config fragments (idempotent). Patches live in patches/<port_patch_set>/ (set in deviceinfo).
shopt -s nullglob
for p in "$HERE/patches/${port_patch_set:?port_patch_set missing in deviceinfo}"/*.patch; do
    if git -C "$KERNEL_DIR" apply --check "$p" 2>/dev/null; then
        git -C "$KERNEL_DIR" apply "$p"
    elif git -C "$KERNEL_DIR" apply --check -R "$p" 2>/dev/null; then
        echo "already applied: $(basename "$p")"
    else
        echo "patch does not apply: $p" >&2; exit 1
    fi
done
cp "$HERE"/config/*.config "$KERNEL_DIR/arch/arm64/configs/vendor/"

# libufdt's pie-gsi mkdtboimg.py is Python 2 only; use the Python 3 version from AOSP android13-gsi (same CLI)
MKDTBO="$BUILD_DIR/downloads/libufdt/utils/src/mkdtboimg.py"
if ! grep -q 'python3' "$MKDTBO"; then
    curl -sfL "https://android.googlesource.com/platform/system/libufdt/+/refs/heads/android13-gsi/utils/src/mkdtboimg.py?format=TEXT" | base64 -d > "$MKDTBO.new"
    grep -q 'python3' "$MKDTBO.new" || { echo "failed to fetch python3 mkdtboimg.py" >&2; exit 1; }
    mv "$MKDTBO.new" "$MKDTBO"
fi

# 3. generic build (kernel, dtbo, boot.img, device tarball)
exec "$TOOLS/build.sh" -b "$BUILD_DIR" -o "$HERE/out" "$@"
