#!/bin/bash -e
################################################################################
##  File:  install-cache-proxy.sh
##  Desc:  Download and Install cache proxy
################################################################################
# Source the helpers for use with the script
source $HELPER_SCRIPTS/os.sh
source $HELPER_SCRIPTS/install.sh

download_url="https://pub-dd18084e939b4f87816c08c17faeb647.r2.dev/cache-proxy-linux-$(get_arch "x64" "arm64").tar.gz"
archive_path=$(download_with_retry "$download_url")

mkdir -p /usr/local/share/cache-proxy
tar xzf "$archive_path" -C /usr/local/share/cache-proxy

cat <<EOF > /etc/systemd/system/cache-proxy.service
[Unit]
Description=Ubicloud Cache Proxy
[Service]
ExecStart=/bin/bash -c "/usr/local/share/cache-proxy/cache-proxy > /var/log/cacheproxy.log 2>&1"
WorkingDirectory=/usr/local/share/cache-proxy
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl start cache-proxy.service
systemctl enable cache-proxy.service
