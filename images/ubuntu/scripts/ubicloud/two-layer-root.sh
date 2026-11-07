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

CONTAINER_LAYER_DIRS="/var/lib/docker/overlay2
/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs
/var/lib/containers/storage/overlay"

# Paths a job writes heavily that the image leaves empty, so they can be put on
# the writable device directly rather than reached through the overlay.
WORKSPACE_DIRS="/home/runner/actions-runner/_work"

# Booting the read-only image would look healthy to the control plane -- the VM
# gets an address and answers ssh -- while every write in the job failed. Stop
# instead, so the failure is attributable and the VM is never handed a job.
die() {
  log "FATAL: $*"
  sleep 1
  echo o > /proc/sysrq-trigger 2>/dev/null
  exit 1
}

mountpoint -q /proc || mount -t proc proc /proc
mountpoint -q /sys || mount -t sysfs sysfs /sys
mountpoint -q /dev || mount -t devtmpfs devtmpfs /dev

# Identify the writable device by what it is, not by what it contains. The
# volume is encrypted with no written-block tracking, so an untouched sector
# decrypts to pseudorandom bytes, and no test of its contents can tell a blank
# device from a used one. What is known for certain is the disk we booted from,
# which the kernel has already mounted at /, and that the cloud-init drive is a
# few hundred KiB. The writable device is the remaining whole disk. Resolved
# from sysfs and mountinfo, so nothing here depends on what any device holds.
root_mm=$(awk '$5=="/" {print $3; exit}' /proc/self/mountinfo)
root_disk=$(basename "$(readlink -f "/sys/dev/block/$root_mm/..")" 2>/dev/null)
[ -n "$root_disk" ] || die "cannot resolve the disk holding / (mountinfo gave '$root_mm')"
log "booted from $root_disk"

upper_dev=""
for dev in /sys/class/block/vd*; do
  name=${dev#/sys/class/block/}
  [ "$name" = "$root_disk" ] && continue
  [ -e "$dev/partition" ] && continue
  [ "$(cat "$dev/size" 2>/dev/null || echo 0)" -gt 2097152 ] || continue
  upper_dev="/dev/$name"
  break
done
[ -n "$upper_dev" ] || die "no virtio disk larger than 1 GiB besides $root_disk"
[ -b "$upper_dev" ] || die "$upper_dev is not a block device"
log "using $upper_dev"

# No journal: the device is discarded when the VM is destroyed, so ordering
# guarantees across a crash buy nothing and cost writes.
mkfs.ext4 -F -q -O ^has_journal \
  -E lazy_itable_init=1,lazy_journal_init=1,nodiscard "$upper_dev" || die "mkfs failed on $upper_dev"
mount -o noatime "$upper_dev" /overlay || die "cannot mount $upper_dev"
mkdir -p /overlay/upper /overlay/work || die "cannot create overlay dirs"

modprobe overlay 2>/dev/null || true
mount -t overlay overlay \
  -o lowerdir=/,upperdir=/overlay/upper,workdir=/overlay/work /newroot || die "cannot assemble overlay"

# A container runtime stacks an overlay of its own for every layer, and the
# kernel refuses one whose upperdir is already on an overlay. Only the
# directories it extracts layers into need a real filesystem; the content blobs
# and metadata beside them are ordinary files and stay on the image.
for store in $CONTAINER_LAYER_DIRS; do
  [ -d "/newroot$store" ] || continue
  mkdir -p "/overlay/stores$store"
  chown --reference="/newroot$store" "/overlay/stores$store"
  chmod --reference="/newroot$store" "/overlay/stores$store"
  mount --bind "/overlay/stores$store" "/newroot$store"
done

# Overlayfs costs 8-15% on every read and write that passes through it, and the
# cost is per operation, so it is worst for the small random I/O a build makes.
# The job workspace does not exist in the image -- the runner creates it -- so
# putting it on the writable device directly hides nothing and keeps the
# heaviest path in a job off the overlay entirely.
for work in $WORKSPACE_DIRS; do
  parent=$(dirname "$work")
  [ -d "/newroot$parent" ] || continue
  mkdir -p "/overlay/work_dirs$work" "/newroot$work" || die "cannot create $work"
  chown --reference="/newroot$parent" "/overlay/work_dirs$work" "/newroot$work"
  chmod --reference="/newroot$parent" "/overlay/work_dirs$work"
  mount --bind "/overlay/work_dirs$work" "/newroot$work" || die "cannot bind $work"
done

# cloud-init puts swap in a file at /swapfile, and the kernel will not swap to a
# file on an overlay. Point that path at the writable device so cloud-init
# creates it there, at whatever size was asked for.
mkdir -p /overlay/swap /newroot/swap
mount --bind /overlay/swap /newroot/swap
ln -sfn /swap/swapfile /newroot/swapfile

mount --move /proc /newroot/proc
mount --move /sys /newroot/sys
mount --move /dev /newroot/dev

cd /newroot || die "cannot enter /newroot"
# The image must stay mounted: it is the overlay's lower layer.
pivot_root . oldroot || die "pivot_root failed"
log "pivoted into overlay"
exec chroot . /lib/systemd/systemd
EOF
chmod 0755 /usr/sbin/ubicloud-two-layer-init

# The layer directories start empty, so the images the build preloaded are not
# there. Copy them back as the runtime starts, from the image rather than from
# a registry.
cat > /usr/sbin/ubicloud-seed-container-layers <<'EOF'
#!/bin/bash
set -u
for store in /var/lib/docker/overlay2 \
             /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs \
             /var/lib/containers/storage/overlay; do
  src="/oldroot$store"
  [ -d "$src" ] || continue
  mountpoint -q "$store" || continue
  [ -z "$(ls -A "$store" 2>/dev/null)" ] || continue
  cp -a "$src/." "$store/" || exit 1
done
EOF
chmod 0755 /usr/sbin/ubicloud-seed-container-layers

for unit in containerd docker; do
  mkdir -p /etc/systemd/system/$unit.service.d
  cat > /etc/systemd/system/$unit.service.d/10-ubicloud-seed.conf <<'EOF'
[Service]
ExecStartPre=/usr/sbin/ubicloud-seed-container-layers
TimeoutStartSec=600
EOF
done

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
