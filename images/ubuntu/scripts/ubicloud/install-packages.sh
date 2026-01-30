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
