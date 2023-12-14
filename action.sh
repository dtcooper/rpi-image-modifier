#!/bin/bash

set -e

# Check we're Linux and have the proper arguments
if [ "${RUNNER_OS}" != "Linux" ]; then
    echo "ERROR: ${RUNNER_OS} not supported"
    exit 1
fi

if [ -z "${ARG_SCRIPT_PATH}" -a -z "${ARG_RUN}" ] || [ "${ARG_SCRIPT_PATH}" -a "${ARG_RUN}" ]; then
    echo 'ERROR: You must specify either a script-path or run input, but not both.'
    exit 1
fi

sudo apt-get update

# qemu-user-static automatically installs aarch64/arm interpeters
sudo apt-get install -y --no-install-recommends \
    pwgen \
    qemu-user-static \
    systemd-container
sudo wget -O /usr/local/bin/pishrink.sh \
    https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh
sudo chmod +x /usr/local/bin/pishrink.sh

TEMP_DIR="/tmp/rpi-image-modifier-$(pwgen -s1 8)"
ORIG_DIR="$(pwd -P)"

mkdir -vp "${TEMP_DIR}/mnt"
cd "${TEMP_DIR}"


if [ -e rpi.img ]; then
    echo 'TESTING: rpi.img already exists'
else
    echo "Downloading ${ARG_BASE_IMAGE_URL}..."
    wget -O rpi.img "${ARG_BASE_IMAGE_URL}"
fi

case "$(file -b --mime-type rpi.img)" in
    application/x-xz) echo 'Decompressing with xz' && mv -v rpi.img rpi.img.xz && xz -T0 -d rpi.img.xz ;;
    application/gzip) echo 'Decompressing with gzip' && mv -v rpi.img rpi.img.gz && gzip -d rpi.img.gz ;;
    application/x-bzip2) echo 'Decompressing with bzip2' && mv -v rpi.img rpi.img.bz2 && bzip2 -d rpi.img.bz2 ;;
    application/x-lzma) echo 'Decompressing with lzma' && mv -v rpi.img rpi.img.lzma && lzma -d rpi.img.lzma ;;
esac

echo "Temporarily expanding image to ${ARG_IMAGE_MAXSIZE}"
fallocate -l "${ARG_IMAGE_MAXSIZE}" rpi.img
LOOPBACK_DEV="$(sudo losetup -fP --show rpi.img)"
echo "Created loopback device ${LOOPBACK_DEV}"

echo 'Expanding partition'
sudo parted rpi.img resizepart 2 '100%FREE'
sudo losetup -d "${LOOPBACK_DEV}"
LOOPBACK_DEV="$(sudo losetup -fP --show rpi.img)"
echo "Re-created looped device ${LOOPBACK_DEV}"

echo 'Resizing second partition'
sudo resize2fs "${LOOPBACK_DEV}p2"

echo 'Mounting image'
sudo mount "${LOOPBACK_DEV}p2" "${TEMP_DIR}/mnt"
sudo mount "${LOOPBACK_DEV}p1" "${TEMP_DIR}/mnt/boot"

if [ "$ARG_MOUNT_REPOSITORY" ]; then
    echo "Mounting ${ORIG_DIR} to /mounted-github-repo in image"
    sudo mkdir -v mnt/mounted-github-repo
    sudo mount -o bind "${ORIG_DIR}" mnt/mounted-github-repo
fi

SCRIPT_NAME="/_$(pwgen -s1 12).sh"

if [ "$ARG_RUN" ]; then
    echo "Generating script to run in image container"
    echo "$ARG_RUN" | sudo tee "mnt${SCRIPT_NAME}"
else
    echo "Copying script to run in image container"
    sudo cp -v "${ORIG_DIR}/${ARG_SCRIPT_PATH}" "mnt${SCRIPT_NAME}"
fi
sudo chmod +x "mnt${SCRIPT_NAME}"

echo "Running script in image container using ${ARG_SHELL}"
sudo systemd-nspawn --directory="${TEMP_DIR}/mnt" --hostname=raspberrypi "${ARG_SHELL}" "${SCRIPT_NAME}"

echo '...Done!'

echo 'Cleaning up image'
sudo rm -v "mnt${SCRIPT_NAME}"
if [ "${ARG_MOUNT_REPOSITORY}" ]; then
    sudo umount mnt/mounted-github-repo
    sudo rmdir -v mnt/mounted-github-repo
fi

echo 'Unmounting and removing loopback device'
sudo umount -R mnt
sudo losetup -d "${LOOPBACK_DEV}"

echo 'Shrinking image'
sudo pishrink.sh rpi.img

echo "Moving image to ${ARG_IMAGE_PATH}"
mv -v rpi.img "${ORIG_DIR}/${ARG_IMAGE_PATH}"

if [ "${ARG_COMPRESS_WITH_XZ}" ]; then
    echo 'Compressing image using xz'
    xz -T0 "${ORIG_DIR}/${ARG_IMAGE_PATH}"
    ARG_IMAGE_PATH="${ARG_IMAGE_PATH}.xz"
fi

echo "image-path=${ARG_IMAGE_PATH}" >> "${GITHUB_OUTPUT}"
