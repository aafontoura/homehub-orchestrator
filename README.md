# HomeHub Setup with Ansible

This guide will walk you through the steps to initialize and configure your Raspberry Pi-based HomeHub using Ansible playbooks.

This repository in dependent of https://github.com/aafontoura/homehub.git

## Clone the Repository

Start by cloning the repository containing the Ansible playbooks and scripts:

```bash
git clone https://github.com/aafontoura/homehub-orchestrator
cd homehub-orchestrator
```

## Initialize the Raspberry Pi Disk

Use the initialize_pi_disk.sh script to flash the Raspberry Pi OS image onto the SD card and preconfigure it for first-time use.

Steps: 1. Find the Target Disk:
Use the diskutil command to identify the correct disk for the SD card.
diskutil list
Look for your SD card’s identifier (e.g., /dev/disk2). 2. Run the Script:
Replace <IMAGE_URL_OR_PATH> with the Raspberry Pi OS image URL or path, with the SD card’s disk identifier, and with the desired password for the pi user.

Example:

```bash
./scripts/initialize_pi_disk.sh https://downloads.raspberrypi.org/raspios_lite_armhf_latest /dev/disk2 “your-secure-password”
```

The script will:
• Download or use the provided OS image.
• Flash the image to the SD card.
• Enable SSH on first boot.
• Set up the pi user with the provided password.

The script requires root privileges to mount the disk, therefore you will be prompted for your system password.

## Insert the SD Card into the Raspberry Pi:

Power on the Raspberry Pi with the SD card initialized in the previous step.

## SSH Access and Key Authentication

### Find the Raspberry Pi’s IP Address:

Use your router or a network scanning tool (e.g., nmap) to find the Raspberry Pi’s IP address.

Example:

```bash
nmap -sn 192.168.1.0/24
```

### Copy the SSH Key to the Raspberry Pi:

Replace <PI_IP> with the Raspberry Pi’s IP address.

```bash
ssh-copy-id pi@<PI_IP>
```

This will allow passwordless SSH access.

### Verify SSH Access:

Test the connection to ensure the SSH key was successfully copied:

```bash
ssh pi@<PI_IP>
```

## Run the HomeHub Setup Playbook

Run the Ansible playbook to configure the Raspberry Pi for the HomeHub environment.

Steps:

## Update the Inventory File:

Edit the inventory file in the repository to match the IP address of the Raspberry Pi:

```
[rpi_homehub]
pi ansible_host=<PI_IP> ansible_user=pi ansible_ssh_private_key_file=~/.ssh/id_rsa
```

## Run the Playbook:

Execute the playbook to set up the HomeHub environment:

```bash
ansible-playbook -i inventory playbooks/setup_homehub.yml
```

Directory Structure
• playbooks/: Contains the Ansible playbooks for configuring the Raspberry Pi.
• scripts/: Contains helper scripts such as initialize_pi_disk.sh.

# Troubleshooting

## SSH Connection Issues:

Ensure:

    •	The Raspberry Pi is powered on and connected to the network.
    •	SSH is enabled on the Raspberry Pi.

## Ansible Errors:

    •	Ensure all dependencies are installed: ansible, python, docker, etc.
    •	Verify the inventory file has the correct Raspberry Pi IP and SSH settings.
