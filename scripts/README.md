# HomeHub Pi Initialization Scripts

This directory contains scripts for automatically provisioning a Raspberry Pi with HomeHub infrastructure.

**Note: These scripts are designed for macOS only.**

## Files

### `initialize_pi_disk.sh`
Main script that flashes Raspberry Pi OS and sets up the first-boot provisioning system.

**Usage:**
```bash
./scripts/initialize_pi_disk.sh \
  --disk /dev/disk2 \
  --password "mypassword" \
  --repo-ssh "git@github.com:user/homehub.git" \
  --ssh-key ~/.ssh/id_ed25519_deploy \
  --wifi-ssid "MyNetwork" \
  --wifi-password "wifipass123"
```

**Required Parameters:**
- `--disk` / `-d` - Target disk device (e.g., `/dev/disk2`)
- `--password` / `-p` - Plain text password for the pi user
- `--repo-ssh` / `-r` - SSH URL for your private repository
- `--ssh-key` / `-s` - Path to SSH private key for repository access

**Optional Parameters:**
- `--image` / `-i` - Custom Raspberry Pi OS image URL or path
- `--wifi-ssid` / `-w` - WiFi network name
- `--wifi-password` / `-k` - WiFi password
- `--wifi-country` / `-c` - WiFi country code (default: NL)
- `--os-user` / `-u` - OS username (default: pi)
- `--portainer-version` - Portainer version (default: 2.25.1)
- `--force-download` / `-f` - Force re-download of cached images

### `firstboot.sh`
Template script that runs once on first boot to provision the Pi with:
- Docker and Docker Compose v2
- HomeHub repository clone
- Portainer container management
- SystemD services for automatic startup
- Security cleanup

This script uses placeholder variables that are replaced by `initialize_pi_disk.sh`:
- `__OS_USER__` - Operating system username
- `__REPO_SSH__` - SSH repository URL
- `__PORTAINER_VERSION__` - Portainer Docker image version

## Process Overview

1. **Preparation**: `initialize_pi_disk.sh` downloads/uses Raspberry Pi OS image
2. **Flashing**: Image is written to SD card using macOS-compatible dd
3. **Boot Setup**: Creates boot partition files:
   - `ssh` - Enables SSH service
   - `userconf` - User credentials
   - `network/wifi-connection.nmconnection` - NetworkManager WiFi configuration (if provided)
   - `wpa_supplicant.conf` - Legacy WiFi configuration fallback (if provided)
   - `firstboot.service` - SystemD unit file
   - `firstboot.sh` - Main provisioning script
   - `keys/id_ed25519*` - SSH deploy keys for repository access
   - `cmdline.txt` - Modified with systemd.run for first-boot execution

4. **First Boot**: Pi automatically:
   - Connects to internet (WiFi via NetworkManager or Ethernet)
   - Updates system packages
   - Installs Docker and Docker Compose
   - Clones HomeHub repository
   - Sets up Portainer web interface
   - Configures SystemD services for automatic startup
   - Cleans up deploy keys and disables first-boot service

## Pre-configured Docker Stacks

The system automatically manages these Docker Compose stacks:
- `docker/pihole` - Network-wide ad blocking
- `docker/mosquitto` - MQTT broker
- `docker/zigbee2mqtt` - Zigbee to MQTT bridge
- `docker/hass-postgres` - PostgreSQL database
- `docker/homeassistant` - Home automation platform

## Post-Setup Access

- **Portainer**: `http://<pi-ip>:9000` - Docker container management
- **SSH**: `ssh <username>@<pi-ip>` - Remote access
- **Logs**: `tail -f /var/log/firstboot.log` - Provisioning progress
- **Services**: `systemctl status portainer homehub-compose` - Service status

## Security Features

- SSH deploy keys are automatically cleaned from boot partition after use
- GitHub SSH host key is pre-installed to prevent MITM attacks
- First-boot service disables itself after successful completion
- All services run with appropriate user permissions
- Deploy keys are read-only for repository access

## Prerequisites

1. **GitHub Deploy Key**: Create a read-only deploy key for your repository
2. **SSH Key Pair**: Have the private key file accessible locally
3. **Internet Connection**: Pi needs connectivity on first boot (WiFi or Ethernet)
4. **Repository Structure**: HomeHub repository with Docker Compose files in expected locations
5. **WiFi Credentials**: If using WiFi, provide SSID and password for automatic connection

## Troubleshooting

- Check `/var/log/firstboot.log` on the Pi for detailed provisioning logs
- Ensure SSH deploy key has repository access
- Verify internet connectivity on first boot
- Monitor SystemD services: `journalctl -u firstboot.service`
- For WiFi issues: Check NetworkManager status with `nmcli device status`
- For legacy WiFi: Check wpa_supplicant logs with `journalctl -u wpa_supplicant`