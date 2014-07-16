#!/bin/bash

set -e
cd /root

# Fix base repos

sed -i /etc/apt/sources.list 's/main$/main contrib non-free/'

cat > /etc/apt/sources.list.d/wheezy-backports.list <<'EOF'
deb http://sft.if.usp.br/debian wheezy-backports main contrib non-free
deb-src http://sft.if.usp.br/debian.org/debian wheezy-backports main contrib non-free
EOF

# Add ZFS repo

wget -N http://archive.zfsonlinux.org/debian/pool/main/z/zfsonlinux/zfsonlinux_2%7Ewheezy_all.deb
dpkg -i zfsonlinux_2~wheezy_all.deb

cat > /etc/apt/sources.list.d/zfs-daily.list <<'EOF'
deb http://archive.zfsonlinux.org/debian wheezy-daily main
deb-src http://archive.zfsonlinux.org/debian wheezy-daily main
EOF


# ...

apt-get update

# Install base packages

tasksel install standard ssh-server
apt-get install locales nano vim



# Install kernel packages

apt-get install firmware-linux-nonfree linux-headers-amd64 \
  linux-{image,headers}-3.12-0.bpo.1-amd64 \
  gdisk dosfstools e2fsprogs

apt-get install debian-zfs

# Check ZFS

modprobe zfs
if dmesg | grep -q 'ZFS:'; then
	echo 'ZFS OK.'
else
	echo 'ZFS module not running, check errors.'
	exit 1
fi





