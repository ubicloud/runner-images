#!/bin/bash
set -euo pipefail

# Inspired by: https://github.com/nv-gha-runners/vm-images/blob/main/linux/installers/nvidia-driver.sh

# Source the helpers for use with the script
source $HELPER_SCRIPTS/etc-environment.sh

KEYRING=cuda-keyring_1.1-1_all.deb
ARCH=x86_64
#NV_DRIVER_VERSION=550
CUDA_TOOLKIT_VERSION=12-4

wget -q "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/${ARCH}/${KEYRING}"
sudo dpkg --install "${KEYRING}"
sudo apt-get update

sudo apt-get -y install "cuda-${CUDA_TOOLKIT_VERSION}" "cudnn9-cuda-12"
prepend_etc_environment_path "/usr/local/cuda/bin"

sudo dpkg --purge "$(dpkg -f "${KEYRING}" Package)"
