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
