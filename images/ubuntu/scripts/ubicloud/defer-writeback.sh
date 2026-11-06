#!/bin/bash -xe

# A runner VM is destroyed at the end of the job it was created for, so every byte it writes is
# discarded minutes later. Those writes still cost host I/O.
#
# When a file is deleted while its pages are still dirty, the kernel frees them without ever
# writing them out. A CI job is full of such files: build trees, virtualenvs, unpacked archives,
# test databases. By default writeback starts after 30 seconds, so they reach the disk anyway.
# Giving them five minutes lets the shorter-lived ones be deleted first, while still bounding how
# much a job can lose on an unclean shutdown.
#
# The ratios are a throttle point, not a cap. A job that genuinely writes a lot crosses them and
# writes exactly as it would have, so nothing fails here that would succeed on a GitHub-hosted
# runner.
cat > /etc/sysctl.d/99-ubicloud-writeback.conf <<'UNIT'
vm.dirty_ratio = 40
vm.dirty_background_ratio = 20
vm.dirty_expire_centisecs = 30000
vm.dirty_writeback_centisecs = 3000
UNIT

# The journal does not outlive the VM either. aws-optimize.sh already does this for the AMI
# builds, which this script does not run for.
sed -i '/^#\?Storage=/d' /etc/systemd/journald.conf
echo 'Storage=volatile' >> /etc/systemd/journald.conf
