# sweetin-halium

Ubuntu Touch (Halium 11) port for the Xiaomi Redmi Note 10 Pro (`sweetin` India / `sweet` global), SM7150, Linux 4.14.
**Status: images build end to end; NOTHING has been booted on hardware.**

## How it is built
Uses UBports' [halium-generic-adaptation-build-tools](https://gitlab.com/ubports/porting/community-ports/halium-generic-adaptation-build-tools).
`./build.sh` is a port-level wrapper that:
1. clones the tools, the LineageOS kernel (`android_kernel_xiaomi_sm6150`, `lineage-21`) and the pinned Halium 11 clang,
2. applies `patches/*.patch` and copies `config/*.config` into the kernel's `arch/arm64/configs/vendor/`,
3. runs the generic build with `deviceinfo` (kernel, DTB, DTBO, `boot.img`, device tarball in `out/`).

Then `./make-images.sh` fetches UBports' rootfs + the generic Halium system image and produces `images/{boot,dtbo,rootfs,system}.img`.

    ./build.sh          # full build
    ./build.sh -k       # kernel + boot.img only
    ./make-images.sh    # flashable images (needs fakeroot jq wget e2fsprogs android-sdk-libsparse-utils)

Host needs (Ubuntu): bc bison build-essential cpio curl fakeroot flex git kmod libelf-dev libssl-dev lz4 python3 unzip wget xz-utils img2simg jq. `python2` is shimmed to `python3` when missing.

## Files
- `deviceinfo`: device/boot parameters, from LineageOS `sweet` / `sm6150-common` board config (header v2, base 0x0, page 4096, DTB in boot image, separate DTBO, UFS `1d84000.ufshc`, `systempart=/dev/mapper/system`).
- `config/halium.config`: container support (namespaces, cgroups, binder, AppArmor, overlayfs, veth).
- `config/halium-checker.config`: generated from Halium's `check-kernel-config -w`.
- `patches/0001`: make clang-only `-mno-implicit-float` conditional (GCC compatibility).
- `patches/0002`: define two WALT sysctl variables that `lineage-21` references but never defines (link error otherwise).

## Verified so far (build side only)
- `./build.sh` completes (pinned Halium 11 clang `r383902`, kernel `lineage-21` + `patches/` + `config/`).
- `boot.img` unpacked and checked: header v2, page 4096, kernel 0x8000, ramdisk 0x1000000, DTB 0x1f00000 (base `xiaomi-sdmmagpie`), intended cmdline.
- `dtbo.img` is a valid DTBO table containing `sweet-sdmmagpie-overlay.dtbo`.
- `make-images.sh` completes; rootfs inspected read-only: contains `/var/lib/lxc/android/android-rootfs.img` (generic Halium container) and this port's `android.conf` overlay.
- Halium's config checker: 114 problems -> 40 after `halium-checker.config`; the rest are legacy symbol names absent from 4.14 plus `DEFAULT_IOSCHED`, `FW_LOADER_USER_HELPER`, `RTC_DRV_CMOS`, `STRICT_DEVMEM`, none expected to block boot.

## NOT verified
- Anything on real hardware: booting, display, touch, modem, Wi-Fi, audio, camera, sensors, GPU, charging.
- Placeholders that need real values: `deviceinfo_bootimg_os_patch_level` (copy from your stock boot.img with `unpack_bootimg.py`) and `GRID_UNIT_PX`/`QTWEBKIT_DPR` in `overlay/.../android.conf`.
- `deviceinfo_kernel_cmdline` may need `console=tty0` for visible boot output; unconfirmed.
- No UBports recovery, so no recovery-based install or OTA yet.

## Artifacts
`artifacts/` holds `boot-sweetin.img.xz` (xz; unpack with `xz -d`) and `dtbo-sweetin.img` with SHA256SUMS. `system.img` (3.4 GB) and `rootfs.img` are too large for git; regenerate with `./make-images.sh`.

## Device facts (LineageOS board config)
A-only, dynamic partitions (`super` ~8.5 GB), boot/recovery 128 MB, dtbo 32 MB, AVB enabled.

## Flashing (UNTESTED, needs your phone; can brick or bootloop it)
Requires an unlocked bootloader (Mi Unlock, waiting period; wipes data) and Android 11 stock firmware so the `vendor` partition matches Halium 11. **First back up** stock `boot`, `dtbo` and `vbmeta`, and keep the stock firmware zip for recovery.

    xz -dk artifacts/boot-sweetin.img.xz
    fastboot flash boot boot-sweetin.img
    fastboot flash dtbo images/dtbo.img
    fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img   # vbmeta.img from stock firmware
    fastboot reboot fastboot                                                    # userspace fastbootd for dynamic partitions
    fastboot flash system images/system.img

The `system` logical partition may need resizing first. If the flash is refused, fix that before retrying. Hardware bring-up (display, modem, audio...) is expected to need further work afterwards.
