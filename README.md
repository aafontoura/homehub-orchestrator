# Flash Raspberry Pi OS Script

A simple and efficient script to download a Raspberry Pi OS image, extract it, flash it onto an SD card or other storage device, and enable SSH for immediate use.

## Table of Contents

- [Introduction](#introduction)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Notes](#notes)
- [Customization](#customization)
- [Troubleshooting](#troubleshooting)
- [Contributors](#contributors)
- [License](#license)

## Introduction

The Flash Raspberry Pi OS Script automates the process of preparing an SD card for use with a Raspberry Pi. It downloads the specified Raspberry Pi OS `.xz` image, extracts it, flashes it to the target device, and sets up SSH by creating an `ssh` file in the boot partition. This simplifies the setup process, saving time and effort.

## Features

- Downloads Raspberry Pi OS images directly from a URL or uses a local `.xz` image.
- Extracts the compressed `.xz` image file.
- Flashes the OS image to a specified disk.
- Automatically enables SSH by adding an `ssh` file to the boot partition.
- Prompts for confirmation to avoid accidental disk erasure.
- Mounts and unmounts the boot partition safely.

## Requirements

- macOS or Linux
- `diskutil` (macOS) or equivalent disk utility
- `xz` installed (available via Homebrew or your package manager)

## Installation

1. Clone the repository or download the script:

   ```bash
   git clone https://github.com/your-username/flash-pi-os-script.git
   cd flash-pi-os-script

   2.	Make the script executable:
   ```

chmod +x flash_pi.sh

Usage 1. List available disks:

diskutil list

Identify the correct disk corresponding to your SD card (e.g., /dev/disk2).

create and encrypted password:

```bash
echo 'your_password' | openssl passwd -6 -stdin
```

    2.	Run the script:

./flash_pi.sh <IMAGE_URL_OR_PATH> <DISK> <ENCRYPTED_PASSWORD>

Example:

./flash_pi.sh https://downloads.raspberrypi.org/raspios_lite_armhf_latest /dev/disk2 $6$6nVy8im3k8CbGCqf$oSb8oGepCWxzH7OnbE8t1y7FA7dD8Tzcsg4FdbEA5byL6l2EuXJlEYFWqDCZBZPJAwRFBqbfmTeBIk4ucSnqf0

    3.	Confirm flashing:

The script will display disk details and ask for confirmation. Type y and press Enter to proceed. 4. Wait for the process to complete:
• The script will extract the OS image, flash it, enable SSH, and unmount the disk.
• Once finished, safely eject your SD card and insert it into your Raspberry Pi.

Notes
• Ensure you have xz installed. On macOS, use Homebrew to install it:

brew install xz

    •	If the boot partition mounts as read-only, you may need to manually remount it as writable or adjust its permissions.
    •	Always double-check the disk name to avoid overwriting the wrong device.

Customization

You can extend the script for additional configuration:
• Add a wpa_supplicant.conf file for Wi-Fi settings.
• Place additional first-boot scripts or configuration files in the boot partition.

Troubleshooting
• Script not running: Ensure the script is executable by running chmod +x flash_pi.sh.
• Disk not detected: Verify the disk name using diskutil list or your system’s disk utility.
• Boot partition is read-only: Remount it as writable using mount or diskutil commands.
• xz command not found: Install it using Homebrew (brew install xz) or your system’s package manager.

Contributors
• Your Name

License

This project is licensed under the MIT License. See the LICENSE file for details.
