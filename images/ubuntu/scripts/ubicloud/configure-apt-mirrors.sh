#!/bin/bash -e
################################################################################
##  File:  configure-apt-mirrors.sh
##  Desc:  Replace /etc/apt/apt-mirrors.txt with a Ubuntu mirror list
##         and refresh apt indexes. Intended for amd64 images that run on
##         Ubicloud VMs, where the Azure mirror is unreachable / very slow.
##
##         The sources.list / sources.list.d/ubuntu.sources files already
##         reference `mirror+file:/etc/apt/apt-mirrors.txt` (configured in
##         build/configure-apt-sources.sh), so only this file needs updating.
################################################################################

echo "https://archive.ubuntu.com/ubuntu/	priority:1
https://security.ubuntu.com/ubuntu/	priority:2" > /etc/apt/apt-mirrors.txt
