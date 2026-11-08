#!/bin/bash -xe

# Split the runner disk in two: the image stays a read-only device the host can
# share between VMs, and every write goes to a second, blank device. The guest
# joins them with dm-snapshot, so the storage backend never has to copy image
# data into a per-VM disk before a write can land.
#
# The alternative is overlayfs, which joins them a level higher, at the
# filesystem. That works, but the kernel refuses an overlay whose upperdir is
# already on an overlay, and a container runtime stacks one per layer. Working
# around that means giving the layer directories a real filesystem, which hides
# the images the build preloaded, which means copying ~3 GiB back at every
# boot -- more writes than the whole arrangement saves, and 14s of boot.
#
# Joining at the block layer has none of that: the guest sees a plain ext4 on a
# normal device, so container runtimes, rename(), hard links and swapfiles all
# behave exactly as they do on a single-disk image. Measured with 4 KiB chunks,
# it writes no more than a plain filesystem (1.01x, against 2.03x at 64 KiB),
# because dm-snapshot skips the copy when a write covers a whole chunk.
#
# The join has to happen before systemd starts. An initramfs would cost the
# ~1.5s GRUB_FORCE_PARTUUID was introduced to save, so the kernel boots the
# image directly and runs an init of ours as PID 1. That init cannot create the
# snapshot straight away: dm-snapshot needs exclusive access to the origin, and
# the origin is the very partition the kernel has mounted as / to run it from.
# So the init first moves itself into a tmpfs holding only busybox and dmsetup,
# unmounts the image to release the partition, and only then builds the
# snapshot and pivots into it. In effect a minimal initramfs assembled at
# runtime, from the image, for the ~0.1s it takes to copy 10 MB.

# Everything stage two needs, so it can run with the image unmounted. busybox is
# the static one; dmsetup is dynamic, so its libraries come along.
STAGE=/usr/lib/ubicloud-dm-stage
rm -rf $STAGE
mkdir -p $STAGE/bin $STAGE/lib
cp /bin/busybox $STAGE/bin/busybox
# busybox sh finds applets through PATH, so each one needs a name. Relative
# links, because the directory is copied into a tmpfs and then becomes /bin.
for applet in sh mount umount pivot_root chroot dd mkdir mknod cp cat echo printf sleep ls blockdev; do
  ln -sf busybox $STAGE/bin/$applet
done
cp /sbin/dmsetup $STAGE/bin/dmsetup
ldd /sbin/dmsetup | awk '/=>/ {print $3}' | while read -r lib; do
  cp "$lib" $STAGE/lib/
done
# The dynamic loader has to sit at the exact path the binary's interpreter
# field names, and that path differs by architecture: /lib64/ld-linux-x86-64.so.2
# on x86_64, /lib/ld-linux-aarch64.so.1 on arm64. Take it from the binary rather
# than assuming. ldd prints the interpreter as the one bare path line.
interp=$(ldd /sbin/dmsetup | awk '!/=>/ && /^[[:space:]]*\// {print $1; exit}')
[ -n "$interp" ] && [ -e "$interp" ] || { echo "cannot find dmsetup's interpreter"; exit 1; }
mkdir -p "$STAGE$(dirname "$interp")"
cp "$interp" "$STAGE$interp"
ls $STAGE/lib "$STAGE$(dirname "$interp")"

cat > /usr/sbin/ubicloud-dm-snapshot-init <<'EOF'
#!/bin/bash
# PID 1, stage one: runs from the read-only image. Works out which device is
# which, stages busybox and dmsetup into a tmpfs, and execs stage two there.
log() { echo "ubicloud-dm-snapshot: $*" > /dev/kmsg 2>/dev/null || true; }

# Booting the image read-only would look healthy to the control plane -- the VM
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

# The partition the kernel mounted as / is the snapshot origin. Resolve it
# through sysfs: udev has not run yet, so /dev/block/<maj:min> does not exist,
# but the kernel itself populates /sys/dev/block and the /dev/vdXN nodes.
root_mm=$(awk '$5=="/" {print $3; exit}' /proc/self/mountinfo)
root_sys=$(readlink -f "/sys/dev/block/$root_mm" 2>/dev/null)
[ -n "$root_sys" ] || die "cannot resolve the root device (mountinfo gave '$root_mm')"
root_part="/dev/$(basename "$root_sys")"
root_disk=$(basename "$(dirname "$root_sys")")
[ -b "$root_part" ] || die "$root_part is not a block device"

# Identify the writable device by what it is, not by what it contains. The
# volume is encrypted with no written-block tracking, so an untouched sector
# decrypts to pseudorandom bytes and no test of its contents can tell a blank
# device from a used one. What is known is the disk we booted from and that the
# cloud-init drive is a few hundred KiB; the writable device is the remaining
# whole disk.
cow_dev=""
for dev in /sys/class/block/vd*; do
  name=${dev#/sys/class/block/}
  [ "$name" = "$root_disk" ] && continue
  [ -e "$dev/partition" ] && continue
  [ "$(cat "$dev/size" 2>/dev/null || echo 0)" -gt 2097152 ] || continue
  cow_dev="/dev/$name"
  break
done
[ -n "$cow_dev" ] || die "no virtio disk larger than 1 GiB besides $root_disk"
[ -b "$cow_dev" ] || die "$cow_dev is not a block device"
log "origin $root_part, writes to $cow_dev"

# Modules live on the image, which stage two will have unmounted.
modprobe dm_snapshot || die "cannot load dm_snapshot"
sectors=$(blockdev --getsz "$root_part") || die "cannot size $root_part"

mount -t tmpfs -o size=64m tmpfs /stage || die "cannot mount the stage tmpfs"
cp -a /usr/lib/ubicloud-dm-stage/. /stage/ || die "cannot populate the stage"
mkdir -p /stage/proc /stage/sys /stage/dev /stage/image /stage/root
cp /usr/sbin/ubicloud-dm-snapshot-stage2 /stage/init2 || die "cannot copy stage two"

export ROOT_PART="$root_part" COW_DEV="$cow_dev" SECTORS="$sectors"
cd /stage || die "cannot enter /stage"
# From here on nothing of ours is mapped from the image.
exec /stage/bin/busybox sh /stage/init2
EOF
chmod 0755 /usr/sbin/ubicloud-dm-snapshot-init

cat > /usr/sbin/ubicloud-dm-snapshot-stage2 <<'EOF'
# PID 1, stage two: runs from the tmpfs under busybox sh, with ROOT_PART,
# COW_DEV and SECTORS from stage one. The image is still mounted at / when this
# starts; the first job is to get out from on top of it.
log() { echo "ubicloud-dm-snapshot: $*" > /dev/kmsg 2>/dev/null || true; }
die() {
  log "FATAL: $*"
  sleep 1
  echo o > /proc/sysrq-trigger 2>/dev/null
  exit 1
}

cd /stage || die "cannot enter /stage"
pivot_root . image || die "pivot_root into the stage failed"
mount --move /image/proc /proc
mount --move /image/sys /sys
mount --move /image/dev /dev
# This is the step the whole arrangement exists for: with the image unmounted,
# the origin partition is free for dm-snapshot to claim.
umount /image || die "cannot unmount the image"
log "image released"

export LD_LIBRARY_PATH=/lib

# A stale exception header on the writable device would be read as a snapshot
# to resume. The device is blank for a new VM, but it decrypts to pseudorandom
# bytes, so clear the head rather than trusting what is there.
dd if=/dev/zero of="$COW_DEV" bs=4096 count=16 conv=fsync 2>/dev/null \
  || die "cannot clear the head of $COW_DEV"

# No udev is running, so libdevmapper has to create the device nodes itself
# rather than wait for a rule to do it.
export DM_DISABLE_UDEV=1
mkdir -p /dev/mapper
dm() { /bin/dmsetup create "$1" --table "$2" || die "dmsetup create $1 failed"; }

# A snapshot is exactly the size of its origin, but the runner was sold the
# size of the writable device, which may be far larger. Split that device:
# the first part is the copy-on-write store, sized so that every chunk of the
# origin can be rewritten once and it still cannot overflow; the rest is plain
# storage appended after the snapshot, and the filesystem is grown into it
# once mounted. The result is one device of the writable disk's full size.
#
# N = transient: the exception table lives in memory only. The VM is destroyed
# at the end of its job, so persisting it would buy nothing and cost writes.
# 8 sectors = 4 KiB chunks, the smallest dm-snapshot allows, which is also the
# filesystem block size: a full-chunk write then needs no copy at all.
cow_total=$(/bin/busybox blockdev --getsz "$COW_DEV") || die "cannot size $COW_DEV"
cow_sectors=$((SECTORS + 2048))
if [ "$cow_total" -gt "$cow_sectors" ]; then
  ext_sectors=$((cow_total - cow_sectors))
  dm ubicow  "0 $cow_sectors linear $COW_DEV 0"
  dm ubiext  "0 $ext_sectors linear $COW_DEV $cow_sectors"
  dm ubisnap "0 $SECTORS snapshot $ROOT_PART /dev/mapper/ubicow N 8"
  printf '0 %s linear /dev/mapper/ubisnap 0\n%s %s linear /dev/mapper/ubiext 0\n' \
    "$SECTORS" "$SECTORS" "$ext_sectors" | /bin/dmsetup create ubiroot || die "dmsetup create ubiroot failed"
  GROW=1
else
  dm ubiroot "0 $SECTORS snapshot $ROOT_PART $COW_DEV N 8"
  GROW=
fi
[ -b /dev/mapper/ubiroot ] || die "/dev/mapper/ubiroot was not created"

mount -o noatime /dev/mapper/ubiroot /root || die "cannot mount /dev/mapper/ubiroot"
mount --move /proc /root/proc
mount --move /sys /root/sys
mount --move /dev /root/dev

cd /root || die "cannot enter the snapshot root"
pivot_root . stage || die "pivot_root into the snapshot failed"
umount -l /stage 2>/dev/null
log "pivoted into the snapshot"
# Grow the filesystem into the appended storage. Done from the real root, which
# has resize2fs; the stage did not need to carry it.
if [ -n "$GROW" ]; then
  chroot . /sbin/resize2fs /dev/mapper/ubiroot >/dev/null 2>&1 || log "resize2fs failed; root stays at image size"
fi
exec chroot . /lib/systemd/systemd
EOF
chmod 0755 /usr/sbin/ubicloud-dm-snapshot-stage2

# Mountpoint for the stage tmpfs, and one stage two pivots the old root onto.
mkdir -p /stage

# generalize-image.sh appends its own GRUB_CMDLINE_LINUX_DEFAULT to
# 50-cloudimg-settings.cfg, so this has to sort after it to survive.
cat > /etc/default/grub.d/60-ubicloud-dm-snapshot.cfg <<'EOF'
GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT init=/usr/sbin/ubicloud-dm-snapshot-init"
EOF

# The device the image lives on is read-only. Dropping the root entry keeps
# systemd-remount-fs and systemd-fsck-root from trying to write to it; /boot
# and /boot/efi are not needed once the kernel is running.
awk '($2 == "/" || $2 == "/boot" || $2 == "/boot/efi") { print "#" $0; next } { print }' \
  /etc/fstab > /etc/fstab.tmp
mv /etc/fstab.tmp /etc/fstab

# grub records initrdless boot failures in /boot/grub/grubenv, which it cannot
# write on a read-only image, so the fallback cannot arm and the unit that
# disarms it only fails the boot.
ln -sf /dev/null /etc/systemd/system/grub-initrd-fallback.service

# The init grows the filesystem itself; cloud-init has no partition to work
# with on a device-mapper root.
cat > /etc/cloud/cloud.cfg.d/99-ubicloud-dm-snapshot.cfg <<'EOF'
growpart:
  mode: "off"
resize_rootfs: false
EOF
