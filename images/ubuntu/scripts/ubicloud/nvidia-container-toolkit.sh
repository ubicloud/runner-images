#!/bin/bash
set -euo pipefail

# Inspired by: https://github.com/nv-gha-runners/vm-images/blob/main/linux/installers/nvidia-container-toolkit.sh

KEYRING="/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg"
APT="/etc/apt/sources.list.d/nvidia-container-toolkit.list"

curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o "${KEYRING}"
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed "s#deb https://#deb [signed-by=${KEYRING}] https://#g" | \
  sudo tee "${APT}"

sudo apt-get update

sudo apt-get install -y --no-install-recommends nvidia-container-toolkit

sudo rm -rf "${APT}" "${KEYRING}"

# Add nvidia runtime to docker and set as default
sudo nvidia-ctk runtime configure --runtime docker --set-as-default

sudo systemctl restart docker
docker info
