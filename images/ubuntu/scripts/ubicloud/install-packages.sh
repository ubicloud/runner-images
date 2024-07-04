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

# Update OpenSSH (https://ubuntu.com/security/CVE-2024-6387)
if is_ubuntu22; then
    apt-get satisfy 'openssh-server (>= 1:8.9p1-3ubuntu0.10)'
fi

if is_ubuntu24; then
    apt-get satisfy 'openssh-server (>= 1:9.6p1-3ubuntu13.3)'
fi
