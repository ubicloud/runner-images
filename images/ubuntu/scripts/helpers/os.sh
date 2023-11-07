#!/bin/bash -e
################################################################################
##  File:  os.sh
##  Desc:  Helper functions for OS releases
################################################################################

is_ubuntu20() {
    lsb_release -rs | grep -q '20.04'
}

is_ubuntu22() {
    lsb_release -rs | grep -q '22.04'
}

is_ubuntu24() {
    lsb_release -rs | grep -q '24.04'
}

is_arm64() {
    test "$(arch)" = "aarch64"
}

get_arch() {
    if is_arm64; then
        echo "$2"
    else
        echo "$1"
    fi
}
