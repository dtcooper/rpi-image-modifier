#!/bin/bash

set -e

TEMP_DIR=/tmp/rpi-image-modifier

# Check we're Linux and have the proper arguments
if [ "${RUNNER_OS}" != "Linux" ]; then
    echo "${RUNNER_OS} not supported"
    exit 1
fi

if [ -z "${ARG_SCRIPT_PATH}" -a -z "${ARG_RUN}" ] || [ "${ARG_SCRIPT_PATH}" -a "${ARG_RUN}" ]; then
    echo 'You must specify either a script-path or run input, but not both.'
    exit 1
fi

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    qemu-user-static \
    systemd-container
sudo wget -O /usr/local/bin/pishrink.sh https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh
sudo chmod +x /usr/local/bin/pishrink.sh

mkdir -p "${TEMP_DIR}/mnt"
pushd "${TEMP_DIR}"


if [ -e rpi.img ]; then
    echo 'TESTING: rpi.img already exists'
else
    echo "Downloading ${ARG_BASE_IMAGE_URL}..."
    wget -O rpi.img "${ARG_BASE_IMAGE_URL}"
fi

case "$(file -b --mime-type rpi.img)" in
    application/x-xz) mv -v rpi.img rpi.img.xz && xz -d rpi.img.xz ;;
    application/gzip) mv -v rpi.img rpi.img.gz && gzip -d rpi.img.gz ;;
    application/x-bzip2) mv -v rpi.img rpi.img.bz2 && bzip2 -d rpi.img.bz2 ;;
    application/x-lzma) mv -v rpi.img rpi.img.lzma && lzma -d rpi.img.lzma ;;
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

echo 'Temporarily copying qemu binaries to mounted image'
for arch in arm aarch64; do
    qemu_bin="$(grep -F interpreter "/proc/sys/fs/binfmt_misc/qemu-${arch}" | awk '{ print $2 }')"
    QEMU_BIN_MNT_DIR="$(dirname "${qemu_bin}")"
    sudo mkdir -p "${QEMU_BIN_MNT_DIR}"
    sudo cp -v "${qemu_bin}" "${TEMP_DIR}/mnt${QEMU_BIN_MNT_DIR}"
done

# Copy additional files
if [ "${ARG_FILES}" -o "${ARG_RUN}" ]; then
    # Parsing this stuff out got too complex for bash
    sudo -E TEMP_DIR="${TEMP_DIR}" "${GITHUB_ACTION_PATH}/file-copy-helper.py"
fi

# Cleanup
echo 'Unmounting and removing loopback device'
sudo umount -R "${TEMP_DIR}/mnt"
sudo losetup -d "${LOOPBACK_DEV}"

echo 'Shrinking image'
sudo pishrink.sh "${TEMP_DIR}/rpi.img"
