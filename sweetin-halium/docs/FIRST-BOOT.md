# First boot: what to do and what to send back

**Everything here is untested on this phone.** Procedures marked *(UBports docs)* come from
https://docs.ubports.com/en/latest/porting/build_and_boot/Boot_debug.html; anything marked *(unconfirmed)* is my
expectation and may be wrong. Flashing can bootloop the device; read the recovery section **before** flashing.

## 0. Before you flash
- Bootloader unlocked (Mi Unlock; wipes data) and the phone on **Android 11** stock firmware (Halium 11 needs a matching `vendor`).
- Backup, from the stock firmware: `boot`, `dtbo`, `vbmeta`, `vbmeta_system`. Keep the full stock fastboot ROM zip for restoring.
- Know how to reach fastboot on Xiaomi: power off, then hold **Volume Down + Power** *(unconfirmed for this model; widely used on Xiaomi phones)*.

## 1. Flash
Both `vbmeta` and `vbmeta_system` must be flashed with verification disabled. A reported first attempt that skipped `vbmeta` bootlooped at the Mi logo; the cause is not yet confirmed to be AVB.

Follow the "Flashing" section in `../README.md`. If `fastboot flash system` is refused (partition too small), stop and
report the exact error; do not force it.

## 2. Did it boot? (a successful boot often shows nothing on screen) *(UBports docs)*
On your Linux host, before powering on the phone:

    dmesg -w

- Seeing a **"GNU/Linux device"** USB message means the system came up and SSH should work.
- Seeing **"Halium initrd Failed to boot"** (or similar) means use the telnet path in section 4.
- Seeing nothing at all: see section 5.

## 3. SSH into the booted system *(UBports docs)*
Find the new RNDIS interface (name looks like `enp0s29u1u1`):

    ip link show

Give it a fake MAC (needed if the default is all zeros) and an address, then bring it up:

    ip link set <devicename> address 02:11:22:33:44:55
    ip address add 10.15.19.100/24 dev <devicename>
    ip link set <devicename> up
    ssh phablet@10.15.19.82

The docs say the password is the one set during `halium-install`. For an image flashed with `fastboot`, I have **not**
confirmed what the default password is, so do not assume one. If SSH asks for a password you do not have, tell me
and we will look at how the image sets credentials.

## 4. Telnet into the initramfs (boot failed early) *(UBports docs)*

    telnet 192.168.2.15

You get here when the rootfs/system image was not found or mounted. Useful first checks once connected:

    cat /proc/cmdline
    ls /dev/mapper /dev/disk/by-partlabel
    dmesg | tail -100

For this port, the cmdline should contain `systempart=/dev/mapper/system` and `androidboot.boot_devices=soc/1d84000.ufshc`.
If `/dev/mapper/system` is missing, dynamic partitions were not set up, which points at the `super`/`system`
flash or the ramdisk's dynparts handling.

## 5. Nothing at all (no USB device, no telnet, black screen)
- Wait about 2 minutes, then check `dmesg -w` again; a reboot loop shows as the USB device repeatedly appearing and vanishing.
- Try a different cable/port, and a direct port instead of a hub.
- This usually means the kernel did not start or crashed very early. Early console is on `ttyMSM0` (serial UART),
  which most users cannot reach; reading it needs a UART adapter on test points *(unconfirmed for this board)*.
- Possible kernel-side next steps for me: add `console=tty0`, enable pstore/ramoops so a crash survives a reboot *(unconfirmed that this kernel's reserved-memory layout supports it)*, or retry with a minimal config.

## 6. Recovering to stock (do this if it will not boot)
1. Reach fastboot (section 0).
2. Flash your **backed-up** stock images:

       fastboot flash boot stock-boot.img
       fastboot flash dtbo stock-dtbo.img
       fastboot --disable-verity --disable-verification flash vbmeta stock-vbmeta.img
       fastboot --disable-verity --disable-verification flash vbmeta_system stock-vbmeta_system.img   # if you backed it up

3. If the phone still will not start, restore the full stock fastboot ROM (including `super`) with Xiaomi's flash tool or the ROM's `flash_all` script.

## 7. What to send me
Paste or attach as much as you have, in this order of usefulness:
1. What you saw on the host with `dmesg -w` right after power-on (copy the lines).
2. Whether SSH (section 3) or telnet (section 4) worked.
3. If you reached a shell: `dmesg`, `cat /proc/cmdline`, `lsblk` and, once the full system is up, `journalctl -b` (if available).
4. The exact `fastboot` output of any step that errored.
5. Your stock `boot.img` (or its `unpack_bootimg.py` output): it gives the true security patch level and lets me
   confirm the boot header values instead of using the LineageOS ones.

Do not post personal data: logs can contain serial numbers, Wi-Fi names and account details. Remove them first.

## 8. Expected to be broken even after it boots
Display scaling (a guess), touch, modem/calls/SMS, mobile data, audio, camera, sensors and GPU acceleration are all
unproven on this port and each needs separate bring-up.
