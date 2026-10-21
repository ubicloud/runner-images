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

# Distrust eMudhra-related root certificates. A "!" prefix in
# /etc/ca-certificates.conf tells update-ca-certificates to drop them from the
# system trust store.
certificates=(
    "mozilla/emSign_ECC_Root_CA_-_G3.crt"
    "mozilla/Comodo_AAA_Services_root.crt"
)
for certificate in "${certificates[@]}"; do
    sed -i "s|^${certificate}$|!&|" /etc/ca-certificates.conf
    if grep -qx "$certificate" /etc/ca-certificates.conf; then
        echo "Failed to distrust ${certificate}"
        exit 1
    fi
done
update-ca-certificates
