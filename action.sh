#!/bin/bash

set -e

mkdir -p /tmp/rpi-image-modifier/mnt
pushd /tmp/rpi-image-modifier

echo "Downloading ${ARG_BASE_IMAGE_URL}..."
wget -qO rpi.img "${ARG_BASE_IMAGE_URL}"

case "$(file -b --mime-type rpi.img)" in
    application/x-xz) mv rpi.img rpi.img.xz && xz -d rpi.img.xz ;;
    application/gzip) mv rpi.img rpi.img.gz && gzip -d rpi.img.gz ;;
    application/x-bzip2) mv rpi.img rpi.img.bz2 && bzip2 -d rpi.img.bz2 ;;
    application/x-lzma) mv rpi.img rpi.img.lzma && lzma -d rpi.img.lzma ;;
esac

if [ "$(ls -1 | wc -l)" -eq 1 ]; then
    echo 'Only one image file expected. (Did your base image URL contain more than one?)'
    exit 1
fi

echo "Temporarily expanding image to ${ARG_IMAGE_MAXSIZE}"
fallocate -l "${ARG_IMAGE_MAXSIZE}" rpi.img
LOOPBACK_DEV="$(sudo losetup -fP --show rpi.img)"
echo "Created loopback device ${LOOPBACK_DEV}"

echo 'Expanding partition'
sudo parted rpi.img resizepart 2 '100%FREE'
sudo losetup -d "${LOOPBACK_DEV}"
LOOPBACK_DEV="$(losetup -fP --show rpi.img)"
echo "Re-created looped device ${LOOPBACK_DEV}"

echo 'Resizing second partition'
sudo resize2fs "${LOOPBACK_DEV}p2"

print 'Mounting image'
sudo mount "${LOOPBACK_DEV}p2" /tmp/rpi-image-modifier/mnt
sudo mount "${LOOPBACK_DEV}p1" /tmp/rpi-image-modifier/mnt/boot
