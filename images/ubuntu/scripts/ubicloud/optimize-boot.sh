#!/bin/bash -xe

# Runners boot once per job, so every second spent booting delays the moment
# the runner picks up the workflow. This script tunes the image so the VM
# becomes sshable faster.

# The NIC is a virtio device on an isolated virtual link and the hypervisor
# assigns its MAC address, so IPv6 duplicate address detection can never find
# a duplicate. DAD keeps the link-local address tentative for ~1 second after
# link-up, and systemd-networkd-wait-online waits for it, which in turn delays
# cloud-init's network stage, sysinit.target and ssh.socket. Disable DAD on
# every non-loopback interface as soon as udev sees it.
cat <<'EOF' > /etc/udev/rules.d/99-ubicloud-no-ipv6-dad.rules
ACTION=="add|move", SUBSYSTEM=="net", KERNEL!="lo", RUN+="/usr/sbin/sysctl -w net.ipv6.conf.$env{INTERFACE}.dad_transmits=0"
EOF

# Skip fsck of /boot and /boot/efi. They gate local-fs.target, and dosfsck of
# the EFI partition alone costs ~0.3 seconds. The image is rebuilt regularly
# and the VM lives for a single job, so filesystem aging is not a concern.
awk '($2 == "/boot" || $2 == "/boot/efi") { $6 = 0 } { print }' /etc/fstab > /etc/fstab.tmp
mv /etc/fstab.tmp /etc/fstab

# Boot splash is useless on a headless VM.
apt-get purge -y plymouth || true

# Runner VMs have no LVM volumes, multipath devices or modems, and live too
# short for PHP session garbage collection to matter.
systemctl disable lvm2-monitor.service || true
systemctl disable multipathd.service multipathd.socket || true
systemctl disable ModemManager.service || true
systemctl disable phpsessionclean.service phpsessionclean.timer || true
