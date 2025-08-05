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

# Install AWS kernel and use it
apt-get update
apt install "linux-image-$(uname -r | cut -d'-' -f1,2)-aws"

# AWS improvements
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/set-time.html
echo 'server 169.254.169.123 prefer iburst minpoll 4 maxpoll 4' >  /etc/chrony/chrony.conf

echo "Storage=Volatile" >> /etc/systemd/journald.conf
echo "RuntimeMaxUse=64M" >> /etc/systemd/journald.conf

apt-get purge plymouth update-notifier-common multipath-tools -y

# speed-up boot
systemctl disable timers.target
#  dev-hugepages.mount
systemctl disable console-setup.service hibinit-agent.service grub-initrd-fallback.service qemu-kvm.service lvm2-monitor.service rsyslog.service ubuntu-advantage.service vgauth.service setvtrgb.service systemd-journal-flush.service
systemctl disable snapd.seeded.service snapd.autoimport.service snapd.core-fixup.service snapd.recovery-chooser-trigger.service snapd.system-shutdown.service
# only on ubuntu 22.04
systemctl disable update-notifier-download.service plymouth-quit.service plymouth-quit-wait.service || true
systemctl disable libvirt-guests.service libvirtd.service systemd-machined.service || true
systemctl disable mono-xsp4.service || true
systemctl disable containerd.service docker.service
systemctl disable apport.service logrotate.service grub-common.service keyboard-setup.service systemd-update-utmp.service systemd-fsck-root.service systemd-tmpfiles-setup.service apparmor.service e2scrub_reap.service || true
systemctl disable ufw.service snapd.service snap.lxd.activate.service snapd.apparmor.service ec2-instance-connect.service snap.amazon-ssm-agent.amazon-ssm-agent.service cron.service || true
# Disable firmware update services, not needed for one-shot runners
systemctl disable fwupd.service fwupd-refresh.service || true
# Disable dpkg-db-backup service, not needed for one-shot runners
systemctl disable dpkg-db-backup.service dpkg-db-backup.timer || true
# Can spawn every 24h, not needed for one-shot runners
systemctl disable apt-news.service esm-cache.service || true
systemctl disable ec2-instance-connect.service ec2-instance-connect-harvest-hostkeys.service || true
systemctl disable ModemManager.service || true

# disable all podman services
find /lib/systemd/system -name 'podman*' -type f -exec systemctl disable {} \;

# disable all php services
find /lib/systemd/system -name 'php*' -type f -exec systemctl disable {} \;

# cleanup
rm -f /home/ubuntu/minikube-linux-amd64
rm -rf /usr/share/doc
rm -rf /usr/share/man
rm -rf /usr/share/icons


rm -rf /usr/local/n
rm -rf /usr/local/doc

rm -rf /var/lib/gems/**/doc ; rm -rf /var/lib/gems/**/cache ; rm -rf /usr/share/ri
rm -rf /usr/local/share/vcpkg/.git
rm -rf /var/lib/ubuntu-advantage

# Remove test folders from cached python versions, they take up a lot of space
for dir in /opt/hostedtoolcache/Python/**/**/lib/python*/test; do
  echo "Removing $dir"
  rm -rf "$dir"
done

for dir in /opt/hostedtoolcache/go/**/**/test; do
  echo "Removing $dir"
  rm -rf "$dir"
done

for dir in /opt/hostedtoolcache/PyPy/**/**/lib/pypy*/test; do
  echo "Removing $dir"
  rm -rf "$dir"
done

# Replace 50-cloudimg-settings with default grub settings
echo "# Cloud Image specific Grub settings for Generic Cloud Images
# CLOUD_IMG: This file was created/modified by the Cloud Image build process

# Use AWS kernel
GRUB_DEFAULT=\"1>2\"

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
