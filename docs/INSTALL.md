# Installing DevOS alongside an existing Linux system

This documents the manual install used for DevOS 1.0 on the reference laptop. It keeps the
existing Ubuntu installation bootable and default, and adds DevOS as a second UEFI boot entry.

## Resulting layout

Reference disk: 477 GiB NVMe, GPT.

| Partition | Size | Filesystem | Role |
|---|---|---|---|
| `nvme0n1p1` | 120 GiB | exFAT | existing storage (was 159 GiB, empty; recreated) |
| `nvme0n1p2` | 38.7 GiB | ext4, label `DevOS` | **DevOS root** |
| `nvme0n1p6` | 1 GiB | FAT32 | shared EFI system partition |
| `nvme0n1p8` | 91.7 GiB | ext4 | existing Ubuntu root (untouched) |
| `nvme0n1p4` | 224.6 GiB | NTFS | existing data (untouched) |

GRUB and the EFI loader live in `\EFI\DevOS\`; the existing system keeps `\EFI\ubuntu\`.
Boot order keeps the existing system first, so a plain reboot returns to Ubuntu. Select **DevOS**
from the firmware boot menu (typically F12) or from the Ubuntu GRUB menu entry.

## 1. Back up first

```bash
B=/path/to/backups/pre-install-$(date +%Y%m%d-%H%M)
sudo mkdir -p "$B"
sudo tar -C /boot/efi -czf "$B/efi-esp.tar.gz" .
sudo sgdisk --backup="$B/gpt-nvme0n1.bin" /dev/nvme0n1
sudo efibootmgr -v | sudo tee "$B/efibootmgr.txt"
sudo cp /etc/fstab "$B/host-fstab.txt"
```

## 2. Make room and create the root partition

Only touch free space or an empty partition. The example shrinks an empty 159 GiB exFAT partition
to 120 GiB and uses the freed ~38.7 GiB.

```bash
sudo umount /run/media/$USER/STORAGE
sudo parted -s /dev/nvme0n1 unit s rm 1 mkpart primary 2048s 251660287s
sudo parted -s /dev/nvme0n1 set 1 msftdata on
sudo parted -s /dev/nvme0n1 unit s mkpart primary ext4 251660288s 332795903s
sudo partprobe /dev/nvme0n1

sudo mkfs.exfat -L STORAGE /dev/nvme0n1p1
sudo mkfs.ext4 -L DevOS -m 1 /dev/nvme0n1p2
sudo mkdir -p /mnt/devos-target
sudo mount /dev/nvme0n1p2 /mnt/devos-target
```

> GPT assigns the lowest free partition number. On this disk the new partition became `p2`, not
> `p9`. Always confirm with `lsblk` before formatting.

## 3. Copy the system

```bash
sudo rsync -aHAX --numeric-ids \
  --exclude='/proc/*' --exclude='/sys/*' --exclude='/dev/*' --exclude='/run/*' \
  --exclude='/tmp/*' --exclude='/mnt/*' --exclude='/media/*' \
  --exclude='/var/cache/apt/archives/*' --exclude='/lost+found' \
  /mnt/devos/rootfs/ /mnt/devos-target/
```

## 4. Configure the installed system

```bash
T=/mnt/devos-target
ROOT_UUID=$(sudo blkid -s UUID -o value /dev/nvme0n1p2)
ESP_UUID=$(sudo blkid -s UUID -o value /dev/nvme0n1p6)

sudo tee $T/etc/fstab >/dev/null <<EOF
UUID=$ROOT_UUID  /          ext4  errors=remount-ro  0 1
UUID=$ESP_UUID   /boot/efi  vfat  umask=0077         0 1
/swapfile        none       swap  sw                 0 0
EOF

sudo fallocate -l 4G $T/swapfile
sudo chmod 600 $T/swapfile
sudo mkswap $T/swapfile

sudo chroot $T adduser --disabled-password --gecos "Dev" dev
echo 'dev:devos' | sudo chroot $T chpasswd
for g in sudo audio video render input plugdev netdev bluetooth lp users cdrom dip floppy kvm; do
  sudo chroot $T adduser dev "$g" >/dev/null 2>&1 || true
done
sudo chroot $T passwd -l root

# remove live-session packages so the installed system boots as a normal system
sudo chroot $T env DEBIAN_FRONTEND=noninteractive apt-get -y purge \
  live-boot live-boot-initramfs-tools live-config live-config-systemd live-tools
```

## 5. Boot loader

```bash
sudo mount -t proc proc $T/proc
sudo mount --bind /dev $T/dev
sudo mount --bind /dev/pts $T/dev/pts
sudo mount --bind /sys $T/sys
sudo mkdir -p $T/boot/efi
sudo mount /dev/nvme0n1p6 $T/boot/efi

sudo tee $T/etc/default/grub >/dev/null <<'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="DevOS"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
GRUB_DISABLE_OS_PROBER=true
EOF

sudo chroot $T grub-install --target=x86_64-efi --efi-directory=/boot/efi \
  --bootloader-id=DevOS --uefi-secure-boot --no-nvram --recheck
sudo chroot $T grub-mkconfig -o /boot/grub/grub.cfg
sudo chroot $T update-initramfs -u -k all
```

## 6. UEFI entry (existing system stays default)

```bash
sudo efibootmgr -c -d /dev/nvme0n1 -p 6 -L DevOS -l '\EFI\DevOS\shimx64.efi'
sudo efibootmgr                      # note the new entry number and the current BootOrder
sudo efibootmgr -o 0000,0001,0002,0003,0004   # keep the existing system first
```

Optionally add DevOS to the existing system's GRUB menu:

```bash
sudo sed -i 's/^#*GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
sudo update-grub
```

The existing system stays the default entry; DevOS appears below it.

## 7. Verify without rebooting (optional)

Boot the installed partition in QEMU with a snapshot so nothing is written:

- Attach the root partition as a raw disk with `snapshot=on`.
- Use a small FAT image as ESP containing `\EFI\DevOS\`.
- Give the test ESP the **same UUID as the real ESP** (`mkfs.vfat -i B81B4D10`). `fstab` mounts
  `/boot/efi` by UUID; if the test ESP has a different UUID, the installed system drops to
  emergency mode even though the real machine would boot fine.

## Rollback

The existing system is untouched and remains first in the boot order:

- Reboot → Ubuntu boots normally.
- To remove DevOS later: delete `\EFI\DevOS\` from the ESP, remove the `DevOS` boot entry with
  `efibootmgr -b <num> -B`, and reformat/delete the DevOS partition.
- Restore the pre-install GPT and ESP from the backups above if needed.

## Notes

- Secure Boot must be **off** for the current image (the kernel package is not signed).
- Do not run `os-prober`/`update-grub` from inside the chroot; run it from the existing system if
  you want DevOS in its menu.
