#!/bin/bash
set -exo pipefail

# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/set-time.html
echo 'server 169.254.169.123 prefer iburst minpoll 4 maxpoll 4' >  /etc/chrony/chrony.conf

echo "Storage=Volatile" >> /etc/systemd/journald.conf
echo "RuntimeMaxUse=64M" >> /etc/systemd/journald.conf

apt-get purge plymouth update-notifier-common multipath-tools -y

# speed-up boot
systemctl disable timers.target
#  dev-hugepages.mount
systemctl disable console-setup.service hibinit-agent.service grub-initrd-fallback.service qemu-kvm.service lvm2-monitor.service rsyslog.service ubuntu-advantage.service vgauth.service setvtrgb.service systemd-journal-flush.service || true
systemctl disable snapd.seeded.service snapd.autoimport.service snapd.core-fixup.service snapd.recovery-chooser-trigger.service snapd.system-shutdown.service || true
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
