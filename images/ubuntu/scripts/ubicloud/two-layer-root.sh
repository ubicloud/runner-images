#!/bin/bash -xe

# Split the runner disk in two: the image stays a read-only device the host can
# share between VMs, and every write goes to a second, blank device. The guest
# joins them with overlayfs, so the storage backend never has to copy image
# data into a per-VM disk before a write can land.
#
# The join has to happen before systemd starts, and the kernel cannot mount an
# overlay as root on its own. Doing it from an initramfs would cost the ~1.5s
# that GRUB_FORCE_PARTUUID was introduced to save, so instead the kernel boots
# the read-only image directly, as it does today, and runs this script as PID 1
# in place of systemd. The script assembles the overlay and pivots into it,
# then execs the real init.

cat > /usr/sbin/ubicloud-two-layer-init <<'EOF'
#!/bin/bash
# PID 1. Assemble the writable overlay over the read-only image, pivot into it
# and hand off to systemd. Any failure falls through to booting the image
# read-only, which is degraded but debuggable.
log() { echo "ubicloud-two-layer: $*" > /dev/kmsg 2>/dev/null || true; }

boot_plain() { log "falling back to read-only boot"; exec /lib/systemd/systemd; }

mountpoint -q /proc || mount -t proc proc /proc
mountpoint -q /sys || mount -t sysfs sysfs /sys
mountpoint -q /dev || mount -t devtmpfs devtmpfs /dev

# The writable device is the one virtio disk that is neither the image we
# booted from nor the cloud-init drive, so it is the one with no filesystem
# signature on it.
upper_dev=""
for d in /dev/vd*; do
  case "$d" in /dev/vda*) continue ;; esac
  [ -b "$d" ] || continue
  [ "$(blockdev --getsize64 "$d" 2>/dev/null || echo 0)" -gt 1073741824 ] || continue
  blkid -p "$d" >/dev/null 2>&1 && continue
  upper_dev="$d"
  break
done
[ -n "$upper_dev" ] || { log "no blank writable device found"; boot_plain; }
log "using $upper_dev"

# No journal: the device is discarded when the VM is destroyed, so ordering
# guarantees across a crash buy nothing and cost writes.
mkfs.ext4 -F -q -O ^has_journal \
  -E lazy_itable_init=1,lazy_journal_init=1,nodiscard "$upper_dev" || boot_plain
mount -o noatime "$upper_dev" /overlay || boot_plain
mkdir -p /overlay/upper /overlay/work || boot_plain

modprobe overlay 2>/dev/null || true
mount -t overlay overlay \
  -o lowerdir=/,upperdir=/overlay/upper,workdir=/overlay/work /newroot || boot_plain

# docker's overlay2 driver refuses an upperdir that is itself on overlayfs, so
# give it a real filesystem on the writable device. This hides the images the
# build preloaded into the read-only base, which still needs an answer.
if [ -d /newroot/var/lib/docker ]; then
  mkdir -p /overlay/docker
  mount --bind /overlay/docker /newroot/var/lib/docker
fi

mount --move /proc /newroot/proc
mount --move /sys /newroot/sys
mount --move /dev /newroot/dev

cd /newroot || boot_plain
# The image must stay mounted: it is the overlay's lower layer.
pivot_root . oldroot || boot_plain
log "pivoted into overlay"
exec chroot . /lib/systemd/systemd
EOF
chmod 0755 /usr/sbin/ubicloud-two-layer-init

# Mountpoints the script needs while the image is still read-only.
mkdir -p /overlay /newroot /oldroot

# generalize-image.sh appends its own GRUB_CMDLINE_LINUX_DEFAULT to
# 50-cloudimg-settings.cfg, so this has to sort after it to survive.
cat > /etc/default/grub.d/60-ubicloud-two-layer.cfg <<'EOF'
GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT init=/usr/sbin/ubicloud-two-layer-init"
EOF

# Every device the image lives on is read-only now. Dropping the root entry
# keeps systemd-remount-fs and systemd-fsck-root from trying to write to it;
# /boot and /boot/efi are not needed once the kernel is running.
awk '($2 == "/" || $2 == "/boot" || $2 == "/boot/efi") { print "#" $0; next } { print }' \
  /etc/fstab > /etc/fstab.tmp
mv /etc/fstab.tmp /etc/fstab

# grub records initrdless boot failures in /boot/grub/grubenv, which it cannot
# write on a read-only image, so the fallback cannot arm and the unit that
# disarms it only fails the boot.
ln -sf /dev/null /etc/systemd/system/grub-initrd-fallback.service

# The root device is read-only and the overlay is already the size of the
# writable device, so there is nothing for cloud-init to grow.
cat > /etc/cloud/cloud.cfg.d/99-ubicloud-two-layer.cfg <<'EOF'
growpart:
  mode: "off"
resize_rootfs: false
EOF
