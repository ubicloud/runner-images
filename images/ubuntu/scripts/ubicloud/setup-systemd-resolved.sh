#!/bin/bash -xe

# Docker containers can't resolve DNS addresses by default on our networking
# setup. We will investigate it in depth, and try to find more generic solution.
# Related issue: https://github.com/ubicloud/ubicloud/issues/507
# Until proper fix, we add custom systemd-resolved configuration.
# Docker gets resolve.conf content from systemd-resolved service.
mkdir -p /etc/systemd/resolved.conf.d
echo "[Resolve]
DNS=9.9.9.9 149.112.112.112 2620:fe::fe 2620:fe::9" > /etc/systemd/resolved.conf.d/Ubicloud.conf
systemctl restart systemd-resolved.service
