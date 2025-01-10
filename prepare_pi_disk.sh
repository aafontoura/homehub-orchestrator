#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <IMAGE_URL_OR_PATH> <DISK>"
  echo "Example: $0 https://downloads.raspberrypi.org/raspios_lite_armhf_latest /dev/disk2"
  exit 1
fi

IMAGE_SOURCE="$1"
DISK="$2"
WORK_DIR="/tmp/rpi-image-work"
MOUNT_POINT="/Volumes/boot"

echo "Creating work directory at $WORK_DIR"
mkdir -p "$WORK_DIR"

# Download the image if it's a URL; otherwise copy it locally.
if [[ "$IMAGE_SOURCE" =~ ^http ]]; then
  echo "Downloading Raspberry Pi OS image..."
  curl -L "$IMAGE_SOURCE" -o "$WORK_DIR/rpi_image.img.xz"
else
  echo "Copying local image file..."
  cp "$IMAGE_SOURCE" "$WORK_DIR/rpi_image.img.xz"
fi

echo "Extracting image from xz..."
xz -d -v -f "$WORK_DIR/rpi_image.img.xz"

IMG_FILE=$(ls "$WORK_DIR"/*.img | head -n 1)
if [ -z "$IMG_FILE" ]; then
  echo "No .img file found after extracting!"
  exit 1
fi

# Show disk details and ask for confirmation
echo "Disk details for $DISK:"
diskutil info "$DISK" || true
echo
read -r -p "You are about to erase and flash this disk. Proceed? [y/N] " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
  echo "Aborting."
  exit 1
fi

echo "Unmounting disk $DISK..."
diskutil unmountDisk force "$DISK"

echo "Flashing $IMG_FILE to $DISK (this may take a while)..."
sudo dd if="$IMG_FILE" of="$DISK" bs=4m conv=sync status=progress
sync

echo "Mounting boot partition..."
BOOT_PARTITION="${DISK}s1"
sudo mkdir -p "$MOUNT_POINT"

# This is a MacOS specific command, it should be simpler in linux
sudo mount -t msdos -o rw "$BOOT_PARTITION" "$MOUNT_POINT"

echo "Enabling SSH on first boot..."
touch "$MOUNT_POINT/ssh"

sleep 1

echo "Unmounting boot partition..."
diskutil unmount "$BOOT_PARTITION"


rm -r "$WORK_DIR"


echo "Done! The SD card is flashed, and SSH is enabled."