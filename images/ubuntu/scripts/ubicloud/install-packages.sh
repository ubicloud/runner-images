#!/bin/bash -xe

source $HELPER_SCRIPTS/os.sh

apt-get update

# sysstat is already installed, but it's not enabled by default
apt-get install sysstat
systemctl enable sysstat
systemctl start sysstat
