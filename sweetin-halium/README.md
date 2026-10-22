# sweetin-halium

Ubuntu Touch (Halium 11) port for the Xiaomi Redmi Note 10 Pro (`sweetin` India / `sweet` global), SM7150, Linux 4.14.
**Status: images build end to end; NOTHING has been booted on hardware.**

## How it is built
Uses UBports' [halium-generic-adaptation-build-tools](https://gitlab.com/ubports/porting/community-ports/halium-generic-adaptation-build-tools).
`./build.sh` is a port-level wrapper that:
1. clones the tools, Xiaomi's official Android 11 kernel source (`MiCode/Xiaomi_Kernel_OpenSource`, branch `sweet-r-oss`, Linux 4.14.180) and the pinned Halium 11 clang,
2. applies `patches/<port_patch_set>/*.patch` and copies `config/*.config` into the kernel's `arch/arm64/configs/vendor/`,
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
- `config/sweet-port.config`: `CONFIG_BUILD_ARM64_DT_OVERLAY=y` (Xiaomi's Android build sets it outside the defconfig; gives the base `sdmmagpie.dtb` + `sweet-sdmmagpie-overlay.dtbo` layout).
- `patches/xiaomi-r-oss/`: builds only the sweet overlay (several reference-board DTBOs in that tree do not compile). `patches/lineage-21/`: obsolete fixes for the abandoned LineageOS 21 kernel.

## Verified so far (build side only)
- `./build.sh` completes on Xiaomi's Android 11 source (pinned Halium 11 clang `r383902`, Linux 4.14.180) with the config/patches in this repo, building from a clean output directory.
- **The built `sdmmagpie.dtb` is byte-identical (same SHA-256) to the base device tree inside a stock Android 11 `boot.img`** from this phone, so the kernel source, toolchain and memory map match the shipped firmware. (The earlier LineageOS 21 tree did not: `pil_adsp_region` 0x1e00000 vs stock 0x2600000.)
- Kernel config contains the Halium needs, incl. USB RNDIS/ECM (the Halium initramfs builds its debug network from RNDIS), namespaces, devtmpfs, AppArmor, binder, pstore.
- `boot.img` unpacked and checked: header v2, page 4096, offsets 0x8000/0x1000000/0x1f00000, `os patch level 2021-12`, intended cmdline incl. `systempart=/dev/mapper/system`.
- `dtbo` is a valid DTBO table containing `sweet-sdmmagpie-overlay.dtbo` (the tools' default image uses a 2048 page size; `artifacts/dtbo-sweetin.img` is rebuilt with 4096 like AOSP, and the stock `dtbo` partition is also expected to work).
- `make-images.sh` completes; rootfs inspected read-only: contains `/var/lib/lxc/android/android-rootfs.img` (generic Halium container) and this port's `android.conf` overlay.
- Halium's config checker: 114 problems -> 40 after `halium-checker.config`; the rest are legacy symbol names absent from 4.14 plus `DEFAULT_IOSCHED`, `FW_LOADER_USER_HELPER`, `RTC_DRV_CMOS`, `STRICT_DEVMEM`, none expected to block boot.

## NOT verified
- Anything on real hardware: booting, display, touch, modem, Wi-Fi, audio, camera, sensors, GPU, charging.
- Placeholders that need real values: `deviceinfo_bootimg_os_patch_level` (copy from your stock boot.img with `unpack_bootimg.py`) and `GRID_UNIT_PX`/`QTWEBKIT_DPR` in `overlay/.../android.conf`.
- `deviceinfo_kernel_cmdline` may need `console=tty0` for visible boot output; unconfirmed.
- No UBports recovery, so no recovery-based install or OTA yet.

## Artifacts
`artifacts/` holds `boot-sweetin.img.xz` (xz; unpack with `xz -d`), `dtbo-sweetin.img` and `vbmeta-disabled.img` with SHA256SUMS; all from the Xiaomi-source build. `system.img` (3.4 GB) and `rootfs.img` are too large for git; regenerate with `./make-images.sh`.

## Device facts (LineageOS board config)
A-only, dynamic partitions (`super` ~8.5 GB), boot/recovery 128 MB, dtbo 32 MB, AVB enabled.

## Flashing (UNTESTED, needs your phone; can brick or bootloop it)
Requires an unlocked bootloader (Mi Unlock, waiting period; wipes data) and Android 11 stock firmware so the `vendor` partition matches Halium 11. **First back up** stock `boot`, `dtbo` and `vbmeta`, and keep the stock firmware zip for recovery.

    xz -dk artifacts/boot-sweetin.img.xz
    fastboot flash boot boot-sweetin.img
    fastboot flash dtbo images/dtbo.img
    fastboot --disable-verity --disable-verification flash vbmeta artifacts/vbmeta-disabled.img
    fastboot --disable-verity --disable-verification flash vbmeta_system artifacts/vbmeta-disabled.img
    fastboot reboot fastboot                                                    # userspace fastbootd for dynamic partitions
    fastboot flash system images/system.img

**Both `vbmeta` and `vbmeta_system` must be flashed** (this phone has both; skipping them left stock signatures that no longer match the replaced `boot`/`system`, and a first test bootlooped at the logo with `vbmeta` skipped). `artifacts/vbmeta-disabled.img` is generated with `avbtool make_vbmeta_image --flags 3`, so stock files are not required for this step.

The `system` logical partition may need resizing first. If the flash is refused, fix that before retrying. Hardware bring-up (display, modem, audio...) is expected to need further work afterwards.
