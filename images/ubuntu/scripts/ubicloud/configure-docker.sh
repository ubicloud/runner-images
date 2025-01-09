#!/bin/bash -xe

DEFAULT_DOCKER_CONFIG='{
  "experimental": false,
  "dns-opts": [
    "attempts:3"
  ]
}'

if [ -f "/etc/docker/daemon.json" ]; then
    existing_config=$(sudo cat /etc/docker/daemon.json)
else
    existing_config="{}"
fi

echo "$existing_config" | jq ". += $DEFAULT_DOCKER_CONFIG" | sudo tee /etc/docker/daemon.json

sudo systemctl restart docker
