#!/bin/bash -e
################################################################################
##  File:  install-terraform.sh
##  Desc:  Install terraform
################################################################################

source $HELPER_SCRIPTS/install.sh
source $HELPER_SCRIPTS/os.sh

# Install Terraform
download_url=$(curl -fsSL https://api.releases.hashicorp.com/v1/releases/terraform/latest | jq -r '.builds[] | select((.arch=="'"$(get_arch "amd64" "arm64")"'") and (.os=="linux")).url')
archive_path=$(download_with_retry "${download_url}")
unzip -qq "$archive_path" -d /usr/local/bin

invoke_tests "Tools" "Terraform"
