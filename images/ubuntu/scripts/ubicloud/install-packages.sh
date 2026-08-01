#!/bin/bash -xe

source $HELPER_SCRIPTS/os.sh
source $HELPER_SCRIPTS/install.sh

apt-get update

# sysstat is already installed, but it's not enabled by default
apt-get install sysstat
systemctl enable sysstat
systemctl start sysstat

# Install ubi CLI
if is_x64; then
    download_url=$(resolve_github_release_asset_url "ubicloud/cli" "test(\"linux-amd64-.*.tar.gz$\")" "latest")
elif is_arm64; then
    download_url=$(resolve_github_release_asset_url "ubicloud/cli" "test(\"linux-arm64-.*.tar.gz$\")" "latest")
else
  echo "Unsupported architecture"
  exit 1
fi
archive_path=$(download_with_retry "$download_url")
tar xzf "$archive_path" -C /usr/local/bin ubi

# Install Wiz sensor
wiz_path="/opt/wiz-sensor-install.sh"
download_with_retry "https://downloads.wiz.io/sensor/sensor_install.sh" "$wiz_path"
chmod 700 "$wiz_path"

# WIZ_PACKAGE_INSTALL_ONLY=1 installs the .deb from Wiz's APT repo and
# stops there: no config files, no API key check, no service start.
sudo WIZ_PACKAGE_INSTALL_ONLY=1 bash "$wiz_path"

# Defensive: make sure the sensor can't start unconfigured on first boot.
# The configure script enables and starts it once credentials are in place.
systemctl disable wiz-sensor.service 2>/dev/null || true

dpkg -s wiz-sensor | grep -E '^(Package|Version|Status)'

rm -f /etc/apt/sources.list.d/wiz.list
