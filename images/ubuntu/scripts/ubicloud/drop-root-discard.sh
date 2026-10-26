#!/bin/bash -xe

# With data=writeback in rootflags (set by configure-environment.sh), the 6.8
# kernel on Ubuntu 22.04 aborts the journal when a discard of freed blocks
# returns EOPNOTSUPP, and the root filesystem is remounted read-only during
# boot. Ubicloud disks and EBS volumes both return it, so drop discard before
# the first reboot with the new rootflags.
sed -i -E '/^[^#[:space:]]+[[:space:]]+\/[[:space:]]/ {
  s/([[:space:]])discard,/\1/
  s/,discard([,[:space:]])/\1/
  s/([[:space:]])discard([[:space:]])/\1defaults\2/
}' /etc/fstab
if findmnt --fstab --noheadings --output OPTIONS --mountpoint / | tr ',' '\n' | grep -qx discard; then
  echo "Failed to remove the discard option from the root filesystem in /etc/fstab"
  exit 1
fi
