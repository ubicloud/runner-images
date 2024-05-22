#!/bin/bash
set -euo pipefail

# Inspired by: https://github.com/nv-gha-runners/vm-images/blob/main/linux/installers/nvidia-driver.sh

KEYRING=cuda-keyring_1.1-1_all.deb
ARCH=x86_64
NV_DRIVER_VERSION=550
CUDA_TOOLKIT_VERSION=12.5

wget -q "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/${ARCH}/${KEYRING}"
sudo dpkg --install "${KEYRING}"
sudo apt-get update

sudo apt-get -y install "nvidia-driver-${NV_DRIVER_VERSION}" "nvidia-cuda-toolkit-${CUDA_TOOLKIT_VERSION}"

sudo dpkg --purge "$(dpkg -f "${KEYRING}" Package)"
