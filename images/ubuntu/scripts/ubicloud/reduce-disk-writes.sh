#!/bin/bash -xe

# A runner VM is destroyed at the end of the job it was created for, so every
# byte it writes is discarded minutes later. Keep the throwaway data out of the
# write path, or let it die in the page cache before writeback runs.
#
# tmpfs is used only where the size is bounded and the content is pure
# throwaway. The workspace itself stays on disk: GitHub-hosted runners put no
# ceiling on it, and a job writing a large file there must not fail on us and
# nowhere else. Deferred writeback keeps its short-lived files off the disk
# without imposing one, and the two-layer init allocates a swapfile so the
# capped mounts below spill rather than fail.

cat >> /etc/fstab <<'UNIT'
tmpfs /root/.cache     tmpfs size=8G,noatime,mode=0700 0 0
tmpfs /var/cache/apt   tmpfs size=4G,noatime,mode=0755 0 0
tmpfs /var/lib/apt/lists tmpfs size=2G,noatime,mode=0755 0 0
tmpfs /tmp             tmpfs size=8G,noatime,mode=1777 0 0
UNIT
mkdir -p /root/.cache /var/cache/apt /var/lib/apt/lists

# Defer writeback far enough that build trees, virtualenvs, unpacked archives
# and test databases are deleted before they are ever written.
cat > /etc/sysctl.d/99-ubicloud-writeback.conf <<'UNIT'
vm.dirty_ratio = 80
vm.dirty_background_ratio = 60
vm.dirty_expire_centisecs = 360000
vm.dirty_writeback_centisecs = 360000
UNIT

# dpkg fsyncs every file it unpacks, which would defeat the above for the most
# write-heavy thing most jobs do.
mkdir -p /etc/dpkg/dpkg.cfg.d
echo force-unsafe-io > /etc/dpkg/dpkg.cfg.d/99-ubicloud-unsafe-io

# The journal does not outlive the VM either.
sed -i '/^#\?Storage=/d' /etc/systemd/journald.conf
echo 'Storage=volatile' >> /etc/systemd/journald.conf
