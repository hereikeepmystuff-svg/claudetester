# sweetin-halium

Ubuntu Touch (Halium 11) port for the Xiaomi Redmi Note 10 Pro (`sweetin` India / `sweet` global), SM7150, Linux 4.14.
**Status: work in progress. Nothing here has been booted on hardware.**

## How it is built
Uses UBports' [halium-generic-adaptation-build-tools](https://gitlab.com/ubports/porting/community-ports/halium-generic-adaptation-build-tools).
`./build.sh` is a port-level wrapper that:
1. clones the tools, the LineageOS kernel (`android_kernel_xiaomi_sm6150`, `lineage-21`) and the pinned Halium 11 clang,
2. applies `patches/*.patch` and copies `config/*.config` into the kernel's `arch/arm64/configs/vendor/`,
3. runs the generic build with `deviceinfo` (kernel, DTB, DTBO, `boot.img`, device tarball in `out/`).

    ./build.sh          # full build
    ./build.sh -k       # kernel + boot.img only

Host needs (Ubuntu): bc bison build-essential cpio curl fakeroot flex git kmod libelf-dev libssl-dev lz4 python3 unzip wget xz-utils img2simg jq. `python2` is shimmed to `python3` when missing.

## Files
- `deviceinfo`: device/boot parameters, from LineageOS `sweet` / `sm6150-common` board config (header v2, base 0x0, page 4096, DTB in boot image, separate DTBO, UFS `1d84000.ufshc`, `systempart=/dev/mapper/system`).
- `config/halium.config`: container support (namespaces, cgroups, binder, AppArmor, overlayfs, veth).
- `config/halium-checker.config`: generated from Halium's `check-kernel-config -w`.
- `patches/0001`: make clang-only `-mno-implicit-float` conditional (GCC compatibility).
- `patches/0002`: define two WALT sysctl variables that `lineage-21` references but never defines (link error otherwise).

## Verified so far
- With the base config `vendor/sdmsteppe-perf_defconfig` (+ `debugfs`, `sweet`, `halium`), GCC 13 built `Image.gz`, `xiaomi-sdmmagpie.dtb` and `sweet-sdmmagpie-overlay.dtbo` (before the checker config was added).
- Halium's config checker: 114 problems -> 40 after `halium-checker.config`. The remaining 40 are legacy symbol names absent from 4.14 (`CGROUP_MEM_RES_CTLR*`, `DEBUG_RODATA`, ...) plus `DEFAULT_IOSCHED`, `FW_LOADER_USER_HELPER`, `RTC_DRV_CMOS`, `STRICT_DEVMEM`, none expected to block boot.
- NOT yet verified: the supported clang build via `build.sh`, the rootfs/system image step, and everything on hardware.

## Device facts (LineageOS board config)
A-only, dynamic partitions (`super` ~8.5 GB), boot/recovery 128 MB, dtbo 32 MB, AVB enabled (needs `vbmeta` with verification disabled).

## Flashing (untested, needs your phone)
Requires an unlocked bootloader (Mi Unlock, waiting period) and Android 11 stock firmware so the `vendor` partition matches Halium 11. Back up the stock `boot`, `dtbo` and `vbmeta` first. Expected sequence, once images exist:
    fastboot flash boot out/boot.img
    fastboot flash dtbo out/dtbo.img
    fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img   # use a vbmeta from stock firmware
    fastboot reboot fastboot                                                    # userspace fastboot for dynamic partitions
    fastboot flash system out/system.img
