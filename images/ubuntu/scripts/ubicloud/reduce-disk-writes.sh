#!/bin/bash -xe

# A runner VM is destroyed at the end of the job it was created for, so every
# byte it writes to its disk is thrown away minutes later. The writes still
# cost real host I/O, and the storage backend amplifies them: a guest write
# into a not-yet-materialised stripe forces the whole stripe to disk. The
# settings below keep throwaway data out of the write path entirely, or let it
# die in the page cache before writeback ever runs.
#
# Measured on a Django CI job (apt install, git clone, venv, pip install,
# 18,627 tests): these take the job from 4.07 GiB of physical writes to
# 2.82 GiB, about -31%, with no change in test-suite time.
#
# Nothing here trades away anything the runner needs. The one thing given up
# is durability across an unclean shutdown, which a single-use VM has no use
# for.

# Reads are writes, under relatime. relatime refreshes a file's atime whenever
# the stored atime is more than a day old, and every file in a freshly built
# image is older than that, so the first read of each file during a job dirties
# an inode. A CI job reads tens of thousands of files it never modifies.
awk '($2 == "/" && $4 !~ /(^|,)noatime(,|$)/) { $4 = $4 ",noatime" } { print }' /etc/fstab > /etc/fstab.tmp
mv /etc/fstab.tmp /etc/fstab

# Let short-lived files die before they are ever written back. Build trees,
# virtualenvs, unpacked archives and test databases are typically created and
# deleted inside one job; if writeback does not run while they exist, they
# never reach the disk at all. Anything that outlives the window is written
# normally, so unlike a tmpfs this has no size limit and cannot fail a job
# that needs more space than RAM.
cat <<'EOF' > /etc/sysctl.d/99-ubicloud-writeback.conf
vm.dirty_ratio = 80
vm.dirty_background_ratio = 60
vm.dirty_expire_centisecs = 360000
vm.dirty_writeback_centisecs = 360000
EOF

# dpkg fsyncs every file it unpacks, which would defeat the deferral above for
# the single most write-heavy thing most jobs do. Ubuntu ships this exact knob
# for throwaway machines such as build chroots.
cat <<'EOF' > /etc/dpkg/dpkg.cfg.d/99-ubicloud-unsafe-io
force-unsafe-io
EOF

# Downloaded .debs are deleted as soon as they are unpacked and are never
# needed again, so they have no reason to touch the disk. Bounded by what a
# job installs, and backed by swap if it ever exceeds RAM.
grep -q '^tmpfs /var/cache/apt/archives ' /etc/fstab || cat <<'EOF' >> /etc/fstab
tmpfs /var/cache/apt/archives tmpfs rw,nosuid,nodev,noatime,size=4G,mode=0755 0 0
EOF

# apt refuses to run if its partial/ directory is missing, and mounting a
# tmpfs over archives/ hides the one baked into the image. Recreate it on
# every boot, after the mount.
cat <<'EOF' > /etc/tmpfiles.d/ubicloud-apt-archives.conf
d /var/cache/apt/archives 0755 root root -
d /var/cache/apt/archives/partial 0700 _apt root -
EOF

# /tmp is deliberately left on disk. Putting it on tmpfs saves a little more,
# but it caps /tmp at a fraction of RAM, and GitHub-hosted runners have no
# such limit, so a job writing a large file there would start failing on us
# and nowhere else. The deferral above already keeps short-lived files in
# /tmp off the disk, without imposing a ceiling.

# The journal is read while the job runs, if at all, and the VM takes it to the
# grave. aws-optimize.sh already does this for the AWS images; the ubicloud
# images were still writing the journal to disk.
sed -i '/^#\?Storage=/d; /^#\?RuntimeMaxUse=/d' /etc/systemd/journald.conf
printf 'Storage=volatile\nRuntimeMaxUse=64M\n' >> /etc/systemd/journald.conf
