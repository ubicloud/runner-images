#!/bin/bash -e
################################################################################
##  File:  install-docker-compose.sh
##  Desc:  Install Docker Compose v1
##  Supply chain security: Docker Compose v1 - checksum validation
################################################################################

# Source the helpers for use with the script
source $HELPER_SCRIPTS/os.sh
source $HELPER_SCRIPTS/install.sh

if is_arm64; then
    # We install v2 instead of v1 because v1 doesn't support aaarch64.
    # Install docker-compose v2 from releases
    binary_path=$(download_with_retry "https://github.com/docker/compose/releases/download/v2.27.1/docker-compose-linux-aarch64")

    # Supply chain security - Docker Compose v2
    external_hash="16e93b9c2fc147d29ca1acbb8ceab6a50a0e26af777f43dc7a753cb883142617"
else
    # Download docker-compose v1 from releases
    binary_path=$(download_with_retry "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-Linux-x86_64")

    # Supply chain security - Docker Compose v1
    external_hash="f3f10cf3dbb8107e9ba2ea5f23c1d2159ff7321d16f0a23051d68d8e2547b323"
fi

use_checksum_comparison "${binary_path}" "${external_hash}"

# Install docker-compose v1
install "${binary_path}" "/usr/local/bin/docker-compose"

invoke_tests "Tools" "Docker-compose v1"
