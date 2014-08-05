#!/bin/bash

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 target_path"
    exit 1
fi

target="$1"

if [ -z "$target" ] || ! [ -d "$target" ]; then
    echo "Invalid target dir '$target'"
    exit 1
fi

post_strap="${BASH_SOURCE[0]}/post_debootstrap.sh"
zfs_prereqs="${BASH_SOURCE[0]}/zfs_prerequisites.sh"

if ! [ -f "$post_strap" ] || ! [ -f "$zfs_prereqs" ]; then
    echo "Missing scripts"
    exit 1
fi

cp "$post_strap" "$zfs_prereqs" "${target}/root/"
mkdir -p "${target}"/{boot,boot/efi,dev,proc,sys} 

mount --bind /dev "${target}/dev"
mount --bind /dev/pts "${target}/dev/pts"
mount --bind /proc "${target}/proc"
mount --bind /sys  "${target}/sys"
