#!/bin/bash -xe

# Downgrade kernel from 6.17.0-1010-azure (shipped with 24.04.4) to
# 6.14.0-1017-azure to keep parity with the previous image.

TARGET_KERNEL="6.14.0-1017-azure"

# Install the target kernel packages
apt-get install -y \
  linux-image-${TARGET_KERNEL} \
  linux-headers-${TARGET_KERNEL} \
  linux-modules-${TARGET_KERNEL} \
  linux-modules-extra-${TARGET_KERNEL} \
  linux-tools-${TARGET_KERNEL}

# Set the target kernel as the default boot entry
sed -i "s/^GRUB_DEFAULT=.*/GRUB_DEFAULT=\"Advanced options for Ubuntu>Ubuntu, with Linux ${TARGET_KERNEL}\"/" /etc/default/grub
update-grub

# Remove all other installed kernel versions
dpkg -l 'linux-image-*' 'linux-headers-*' 'linux-modules-*' 'linux-tools-*' | \
  awk '/^ii/ && $2 !~ /'"${TARGET_KERNEL}"'/ && $2 !~ /generic/ { print $2 }' | \
  xargs -r apt-get purge -y

# Clean up
apt-get autoremove -y
apt-get clean
