#!/bin/bash
set -exo pipefail

cat > /root/.gemrc <<EOF
gem: --no-document
EOF

# will be installed as classic debian package, to save space
snap remove amazon-ssm-agent
snap remove core18
snap remove lxd
snap remove core20
rm -rf /var/lib/snapd/seed/snaps

# avoid nvme0n1: Process '/usr/bin/unshare -m /usr/bin/snap auto-import --mount=/dev/nvme0n1' failed with exit code 1.
snap set system experimental.hotplug=false

# saves ~1s on cloud-init (`cloud-init analyze blame`)
arch=$(dpkg --print-architecture)
codename=$(lsb_release --codename -s)
sed -i 's|release = util.lsb_release()\["codename"\].*|release = "'$codename'"|w /dev/stdout' /usr/lib/python3/dist-packages/cloudinit/config/cc_apt_configure.py | grep $codename
sed -i 's|util.get_dpkg_architecture()|"'$arch'"|w /dev/stdout' /usr/lib/python3/dist-packages/cloudinit/config/cc_apt_configure.py | grep $arch
sed -i 's|util.get_dpkg_architecture()|"'$arch'"|w /dev/stdout' /usr/lib/python3/dist-packages/cloudinit/distros/debian.py | grep $arch
