#!/bin/bash
# Turn the device tarball from ./build.sh into flashable images (same steps as UBports' gsi-port-ci.yml).
# Downloads ~1 GB (UBports rootfs + generic Halium system image). Output: images/{boot,dtbo,rootfs,system}.img
# Needs: fakeroot jq wget xz-utils e2fsprogs android-sdk-libsparse-utils (img2simg) and ./build.sh already run.
set -euo pipefail
cd "$(dirname "$0")"
[ -f out/device_sweetin.tar.xz ] || { echo "run ./build.sh first" >&2; exit 1; }
./build/prepare-fake-ota.sh out/device_sweetin.tar.xz ota
mkdir -p images
./build/system-image-from-ota.sh ota/ubuntu_command images
ls -la images
