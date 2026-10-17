# sweetin-halium

Work-in-progress Halium 11 / Ubuntu Touch port for the Redmi Note 10 Pro
(`sweetin`, SM7150 "atoll", Linux 4.14). Status: kernel build in progress; nothing has been booted on hardware.

## Layout
- `config/halium.config`: container/Halium kernel options merged over the device defconfig.
- `patches/`: local fixes applied to the kernel source (`src/kernel`).
- `src/` (ignored): clones of LineageOS `android_kernel_xiaomi_sm6150` (branch `lineage-21`) and `Halium/halium-devices` (`halium-11.0`).
- `out/` (ignored): kernel build output.

## Build the kernel
    cd src/kernel
    make O=../../out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- vendor/atoll-perf_defconfig vendor/sweet.config
    scripts/kconfig/merge_config.sh -m -O ../../out ../../out/.config ../../config/halium.config
    make O=../../out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
    git apply ../../patches/*.patch
    make O=../../out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- KCFLAGS=-Wno-error -j4 Image.gz dtbs

Needs: gcc-aarch64-linux-gnu, binutils-aarch64-linux-gnu, flex, bison, bc, cpio, libssl-dev, device-tree-compiler.

## Known gaps
- Halium 11 is GSI-style (generic `halium_arm64` system image); a prebuilt system image still has to be sourced.
- Needs an unlocked bootloader and Android 11 stock vendor firmware on the device.
