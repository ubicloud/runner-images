#!/bin/bash -e
################################################################################
##  File:  install-tc-app.sh
##  Desc:  Download and Install tcapp
################################################################################

# Source the helpers for use with the script
source $HELPER_SCRIPTS/os.sh
source $HELPER_SCRIPTS/install.sh

download_url=$(resolve_github_release_asset_url "velioglu/exec_repo" 'test("tcapp-linux-'"$(get_arch "x64" "arm64")"'-[0-9]+\\.[0-9]{3}\\.[0-9]+\\.tar\\.gz$")' "latest")
archive_name="${download_url##*/}"
archive_path=$(download_with_retry "$download_url")

mkdir -p /usr/local/share/tcapp
tar xzf "$archive_path" -C /usr/local/share/tcapp

cat <<EOF > /etc/systemd/system/tcapp.service
[Unit]
Description=Ubicloud Cache Proxy

[Service]
ExecStart=/bin/bash -c "/usr/local/share/tcapp/tcapp > ~/cacheproxy.log 2>&1"
WorkingDirectory=/usr/local/share/tcapp
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start tcapp.service
systemctl enable tcapp.service

mkdir -p /opt/tcapp-cache
mv "$archive_path" "/opt/tcapp-cache/$archive_name"
