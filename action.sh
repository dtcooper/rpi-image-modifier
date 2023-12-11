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

TEMP_DIR=/tmp/rpi-image-modifier
ORIG_DIR="$(pwd -P)"

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    qemu-user-static \
    systemd-container
sudo wget -O /usr/local/bin/pishrink.sh https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh
sudo chmod +x /usr/local/bin/pishrink.sh

mkdir -p "${TEMP_DIR}/mnt"
cd "${TEMP_DIR}"


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
    QEMU_BIN_DIR="${TEMP_DIR}/mnt$(dirname "${qemu_bin}")"
    sudo mkdir -p "${QEMU_BIN_DIR}"
    sudo cp -v "${qemu_bin}" "${QEMU_BIN_DIR}"
done

if [ "$ARG_MOUNT_REPOSITORY" ]; then
    echo "Mounting ${ORIG_DIR} to /github-repo in image"
    sudo mkdir mnt/github-repo
    sudo mount -o bind "${ORIG_DIR}" "mnt/github-repo"
fi

exit 0

SCRIPT_NAME="${TEMP_DIR}/_$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 10).sh"

if [ "$ARG_RUN" ]; then
    echo "Generating script to run in image container"
    echo -e "#/bin/bash\n" > "${SCRIPT_NAME}"
    echo "$ARG_RUN" >> "${SCRIPT_NAME}"
else
    echo "Copying script to run in image container"
    cp -v "${ORIG_DIR}/${ARG_SCRIPT_PATH}" "${SCRIPT_NAME}"
fi
chmod +x "${SCRIPT_NAME}"

echo 'Running script in image container'
sudo systemd-nspawn --directory="${TEMP_DIR}/mnt" --hostname=raspberrypi "${SCRIPT_NAME}"

echo '...Done!'

# echo 'Unmounting and removing loopback device'
# sudo umount -R "${TEMP_DIR}/mnt"
# sudo losetup -d "${LOOPBACK_DEV}"

# echo 'Shrinking image'
# sudo pishrink.sh "${TEMP_DIR}/rpi.img"
