#!/bin/bash -xe

DOCKER_DAEMON_CONFIG='{
  "experimental": false,
  "registry-mirrors": ["https://mirror.gcr.io"],
  "dns-opts": [
    "attempts:3"
  ]
}'

BUILDKIT_CONFIG='
[registry."docker.io"]
  mirrors = ["mirror.gcr.io"]

[registry."mirror.gcr.io"]
  http = false
  insecure = false'


if [ -f "/etc/docker/daemon.json" ]; then
    existing_config=$(sudo cat /etc/docker/daemon.json)
else
    existing_config="{}"
fi
echo "$existing_config" | jq ". += $DOCKER_DAEMON_CONFIG" | sudo tee /etc/docker/daemon.json

sudo mkdir -p /etc/buildkit
echo "$BUILDKIT_CONFIG" | sudo tee -a /etc/buildkit/buildkitd.toml

sudo systemctl daemon-reload
sudo systemctl restart docker

# Cache commonly used docker images
# GitHub removed its caching of docker images
# https://github.com/ubicloud/runner-images/commit/dc01c37dc5ade2ec2616023f0aa829c32a5f1018
images=(
    "moby/buildkit:latest"
    "alpine:3.21"
    "alpine:3.22"
    "alpine:3.23"
    "debian:13"
    "node:22"
    "node:24"
    "node:22-alpine"
    "node:24-alpine"
    "ubuntu:22.04"
    "ubuntu:24.04"
)

for image in "${images[@]}"; do
    docker pull "$image"
done
