#!/bin/bash -xe

source $HELPER_SCRIPTS/os.sh

# To able run this image in Ubicloud, we need to remove some Azure specific
# configurations

sleep 30

# It's Hyper-V Key Value Pair daemon, which is not needed in Ubicloud
# It blocks booting the VM if it's not disabled
systemctl disable hv-kvp-daemon.service

# Remove Hyper-V line from chrony config file
sed -i 's/^refclock PHC \/dev\/ptp_hyperv/# &/' /etc/chrony/chrony.conf
systemctl restart chronyd

# Delete the Azure Linux Agent
apt -y purge walinuxagent
rm -rf /var/lib/waagent
rm -f /var/log/waagent.log

# Clean up cloud-init logs and cache to run it again on first boot
cloud-init clean --logs --seed

# Delete Azure specific cloud-init config files
rm -rf /etc/cloud/cloud.cfg.d/90-azure.cfg
rm -rf /etc/cloud/cloud.cfg.d/10-azure-kvp.cfg

# Replace cloud-init datasource_list with default list
echo "# to update this file, run dpkg-reconfigure cloud-init
datasource_list: [ NoCloud, ConfigDrive, OpenNebula, DigitalOcean, Azure, AltCloud, OVF, MAAS, GCE, OpenStack, CloudSigma, SmartOS, Bigstep, Scaleway, AliYun, Ec2, CloudStack, Hetzner, IBMCloud, Oracle, Exoscale, RbxCloud, UpCloud, VMware, Vultr, LXD, NWCS, None ]" > /etc/cloud/cloud.cfg.d/90_dpkg.cfg

# Delete Azure specific grub config files
rm -rf /etc/default/grub.d/40-force-partuuid.cfg
rm -rf /etc/default/grub.d/50-cloudimg-settings.cfg

# Replace 50-cloudimg-settings with default grub settings
echo "# Cloud Image specific Grub settings for Generic Cloud Images
# CLOUD_IMG: This file was created/modified by the Cloud Image build process

# Set the recordfail timeout
GRUB_RECORDFAIL_TIMEOUT=0

# Do not wait on grub prompt
GRUB_TIMEOUT=0

# Set the default commandline
GRUB_CMDLINE_LINUX_DEFAULT=\"console=tty1 console=ttyS0\"

# Set the grub console type
GRUB_TERMINAL=console" >> /etc/default/grub.d/50-cloudimg-settings.cfg

# Update grub
update-grub

# Remove all existing ssh host keys
rm /etc/ssh/ssh_host_*key*

# Delete the root password
passwd -d root

# Rebuild apt lists from scratch
if is_ubuntu22; then
    rm -vf /var/lib/apt/lists/* || true
    apt-get update
fi

sync

# Delete the packer account
touch /var/run/utmp
userdel -f -r packer
