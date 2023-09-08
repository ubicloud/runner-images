#!/bin/bash -xe

source $HELPER_SCRIPTS/os.sh

apt-get update

# sysstat is already installed, but it's not enabled by default
apt-get install sysstat
systemctl enable sysstat
systemctl start sysstat

# Install nftables and enable it because it's not installed by default in Ubuntu 20.04
if is_ubuntu20; then
    apt-get install nftables
    systemctl start nftables
    systemctl enable nftables
fi
