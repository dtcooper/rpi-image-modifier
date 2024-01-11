#!/bin/bash

set -e

# Check we're Linux and have the proper arguments
if [ "${RUNNER_OS}" != "Linux" ]; then
    echo "ERROR: ${RUNNER_OS} not supported"
    exit 1
fi

if [ -z "${__ARG_SCRIPT_PATH}" -a -z "${__ARG_RUN}" ] || [ "${__ARG_SCRIPT_PATH}" -a "${__ARG_RUN}" ]; then
    echo 'ERROR: You must specify either a script-path or run input, but not both.'
    exit 1
fi

if [ "${__ARG_ENV_VARS}" ] && echo "${__ARG_ENV_VARS}" | grep -vqE '^([a-zA-Z_][a-zA-Z_0-9]*,)*([a-zA-Z_][a-zA-Z_0-9]*)$'; then
    echo 'ERROR: Argument env-vars was malformed, must be a comma-separated list of variables.'
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

NEEDS_CACHE_COPY=
if [ "${__ARG_CACHE}" -a -e /tmp/rpi-cached.img ]; then
    echo "Using cached image for ${__ARG_BASE_IMAGE_URL}"
    mv -v /tmp/rpi-cached.img rpi.img
else
    echo "Downloading ${__ARG_BASE_IMAGE_URL}..."
    wget -O rpi.img "${__ARG_BASE_IMAGE_URL}"
    NEEDS_CACHE_COPY=1
fi

case "$(file -b --mime-type rpi.img)" in
    application/x-xz) echo 'Decompressing with xz' && mv -v rpi.img rpi.img.xz && xz -T0 -d rpi.img.xz ;;
    application/gzip) echo 'Decompressing with gzip' && mv -v rpi.img rpi.img.gz && gzip -d rpi.img.gz ;;
    application/x-bzip2) echo 'Decompressing with bzip2' && mv -v rpi.img rpi.img.bz2 && bzip2 -d rpi.img.bz2 ;;
    application/x-lzma) echo 'Decompressing with lzma' && mv -v rpi.img rpi.img.lzma && lzma -d rpi.img.lzma ;;
esac

if [ "${__ARG_CACHE}" ] && [ "${NEEDS_CACHE_COPY}" ]; then
    echo 'Copying image for cache (got a cache miss)'
    cp -v rpi.img /tmp/rpi-cached.img
fi

echo "Temporarily expanding image to ${__ARG_IMAGE_MAXSIZE}"
fallocate -l "${__ARG_IMAGE_MAXSIZE}" rpi.img
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
sudo mount -v "${LOOPBACK_DEV}p2" "${TEMP_DIR}/mnt"

if grep -qF /boot/firmware "${TEMP_DIR}/mnt/etc/fstab"; then
    BOOT_MOUNTPOINT=/boot/firmware
else
    BOOT_MOUNTPOINT=/boot
fi
sudo mount -v "${LOOPBACK_DEV}p1" "${TEMP_DIR}/mnt/${BOOT_MOUNTPOINT}"

if [ "$__ARG_MOUNT_REPOSITORY" ]; then
    echo "Mounting ${ORIG_DIR} to /mounted-github-repo in image"
    sudo mkdir -v mnt/mounted-github-repo
    sudo mount -vo bind "${ORIG_DIR}" mnt/mounted-github-repo
fi

SCRIPT_NAME="/_$(pwgen -s1 12).sh"

if [ "$__ARG_RUN" ]; then
    echo "Generating script to run in image container"
    echo -e "set -e\n" | sudo tee "mnt${SCRIPT_NAME}"
    echo "$__ARG_RUN" | sudo tee -a "mnt${SCRIPT_NAME}"
else
    echo "Copying script to run in image container"
    sudo cp -v "${ORIG_DIR}/${__ARG_SCRIPT_PATH}" "mnt${SCRIPT_NAME}"
fi
sudo chmod +x "mnt${SCRIPT_NAME}"

echo "Running script in image container using ${__ARG_SHELL}"
EXTRA_SYSTEMD_NSPAWN_ARGS=()
if [ "${__ARG_ENV_VARS}" ]; then
    echo "Using environment variables: $(echo "${__ARG_ENV_VARS}" | sed 's/,/, /g')"
    for ENV_VAR in $(echo "${__ARG_ENV_VARS}" | sed 's/,/ /g'); do
        EXTRA_SYSTEMD_NSPAWN_ARGS+=("--setenv=${ENV_VAR}=${!ENV_VAR}")
    done
fi

sudo systemd-nspawn --directory="${TEMP_DIR}/mnt" --hostname=raspberrypi "${EXTRA_SYSTEMD_NSPAWN_ARGS[@]}" "${__ARG_SHELL}" "${SCRIPT_NAME}"

echo '...Done!'

echo 'Cleaning up image'
sudo rm -v "mnt${SCRIPT_NAME}"
if [ "${__ARG_MOUNT_REPOSITORY}" ]; then
    sudo umount -v mnt/mounted-github-repo
    sudo rmdir -v mnt/mounted-github-repo
fi

echo 'Unmounting and removing loopback device'
sudo umount -vR mnt
sudo losetup -d "${LOOPBACK_DEV}"

echo 'Shrinking image'
sudo pishrink.sh -s rpi.img

echo "Moving image to ${__ARG_IMAGE_PATH}"
mv -v rpi.img "${ORIG_DIR}/${__ARG_IMAGE_PATH}"

if [ "${__ARG_COMPRESS_WITH_XZ}" ]; then
    echo 'Compressing image using xz (this may take a while)'
    xz -T0 "${ORIG_DIR}/${__ARG_IMAGE_PATH}"
    __ARG_IMAGE_PATH="${__ARG_IMAGE_PATH}.xz"
fi

echo "Setting output: image-path=${__ARG_IMAGE_PATH}"
echo "image-path=${__ARG_IMAGE_PATH}" >> "${GITHUB_OUTPUT}"
