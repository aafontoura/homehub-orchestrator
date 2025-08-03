#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# HomeHub First Boot Provisioning Script
# =============================================================================
# This script runs once on first boot to automatically provision a Raspberry Pi
# with Docker, clone the HomeHub repository, and start all services.
#
# The script is designed to be robust and idempotent, with comprehensive logging
# and error handling. It will disable itself after successful completion.
#
# This script can be called via systemd.run from cmdline.txt (macOS flow)
# or via systemd service (Linux flow).
# =============================================================================

# Ensure we're root and on target
set -euo pipefail

# ----- Configuration (will be replaced by initialize_pi_disk.sh) -----
OS_USER="__OS_USER__"
REPO_SSH="__REPO_SSH__"
PORTAINER_VERSION="__PORTAINER_VERSION__"
# ---------------------------------------------------------------------

APP_DIR="/home/${OS_USER}/homehub"
COMPOSE_STACKS=(
  "docker/pihole"
  "docker/mosquitto"
  "docker/zigbee2mqtt"
  "docker/hass-postgres"
  "docker/homeassistant"
)
PORTAINER_IMAGE="portainer/portainer-ce:${PORTAINER_VERSION}"
PORTAINER_DATA="/home/${OS_USER}/config/portainer-ce"

# Redirect all output to log file with timestamps
exec 1> >(tee -a /var/log/firstboot.log) 2>&1
echo "[firstboot] Starting HomeHub provisioning at $(date -Iseconds)"
echo "[firstboot] OS User: ${OS_USER}"
echo "[firstboot] Repository: ${REPO_SSH}"
echo "[firstboot] Portainer Version: ${PORTAINER_VERSION}"

# Function to log with timestamp
log() {
    echo "[firstboot] $(date -Iseconds): $*"
}

# Function to handle errors
error_exit() {
    log "ERROR: $1"
    log "FirstBoot provisioning FAILED. Check /var/log/firstboot.log for details."
    exit 1
}

# Install and enable the persistent firstboot service (for Linux flow)
if [ -f /boot/firstboot.service ]; then
    install -m 0644 /boot/firstboot.service /etc/systemd/system/firstboot.service
    systemctl enable firstboot.service || log "Warning: Failed to enable firstboot service"
fi

# Remove systemd.run from cmdline.txt so we don't run again next boot
if [ -f /boot/cmdline.txt ]; then
    sed -i 's/ *systemd\.run=[^ ]*//; s/ *systemd\.run_success_action=[^ ]*//; s/ *systemd\.run_failure_action=[^ ]*//' /boot/cmdline.txt || log "Warning: Failed to clean cmdline.txt"
fi

# Make this script available after reboot if ever needed for debugging
install -m 0755 /boot/firstboot.sh /usr/local/sbin/firstboot.sh || true

log "Setting up WiFi connection if configured..."
# Setup WiFi using NetworkManager if configuration exists
if [ -d /boot/network ]; then
    log "Found NetworkManager WiFi configuration, setting up connection..."
    
    # Install NetworkManager if not already present
    if ! command -v nmcli &> /dev/null; then
        log "Installing NetworkManager..."
        apt-get -y install network-manager || log "Warning: Failed to install NetworkManager"
    fi
    
    # Copy all NetworkManager connection files from /boot/network
    install -d -m 0700 /etc/NetworkManager/system-connections || log "Warning: Failed to create NetworkManager directory"
    for f in /boot/network/*.nmconnection; do
        [ -e "$f" ] || continue
        dst="/etc/NetworkManager/system-connections/$(basename "$f")"
        log "Installing WiFi profile: $(basename "$f")"
        install -m 600 "$f" "$dst" || log "Warning: Failed to copy NetworkManager config"
    done
    
    # Reload NetworkManager connections
    nmcli connection reload || systemctl restart NetworkManager || log "Warning: Failed to reload NetworkManager"
    
    # Wait a moment for NetworkManager to process the configuration
    sleep 5
    
    log "WiFi configuration applied"
elif [ -f /boot/wpa_supplicant.conf ]; then
    log "Found legacy wpa_supplicant configuration, using fallback method..."
    # Copy wpa_supplicant.conf to the proper location
    install -m 0600 /boot/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf || log "Warning: Failed to copy wpa_supplicant.conf"
    
    # Restart wpa_supplicant service
    systemctl restart wpa_supplicant || log "Warning: Failed to restart wpa_supplicant"
    log "Legacy WiFi configuration applied"
else
    log "No WiFi configuration found, using Ethernet connection"
fi

log "Starting system updates..."
apt-get update || error_exit "Failed to update package lists"
apt-get -y upgrade || error_exit "Failed to upgrade packages"
apt-get -y install git ca-certificates curl || error_exit "Failed to install basic packages"

log "Installing Docker and Docker Compose v2..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh || error_exit "Failed to install Docker"
    usermod -aG docker "${OS_USER}" || error_exit "Failed to add user to docker group"
    systemctl enable docker || error_exit "Failed to enable Docker service"
    log "Docker installed successfully"
else
    log "Docker already installed, skipping installation"
fi

log "Setting up SSH for repository access..."
# Prepare SSH directory with proper permissions
install -d -m 0700 "/home/${OS_USER}/.ssh" || error_exit "Failed to create .ssh directory"

# Install SSH keys for repository access
if [ -f /boot/keys/id_ed25519 ]; then
    install -m 0600 /boot/keys/id_ed25519 "/home/${OS_USER}/.ssh/id_ed25519" || error_exit "Failed to install private SSH key"
    [ -f /boot/keys/id_ed25519.pub ] && install -m 0644 /boot/keys/id_ed25519.pub "/home/${OS_USER}/.ssh/id_ed25519.pub"
    chown -R "${OS_USER}:${OS_USER}" "/home/${OS_USER}/.ssh" || error_exit "Failed to set SSH directory ownership"
    
    # Pin GitHub host key to avoid TOFU prompts (Ed25519 host key)
    # Source: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
    log "Adding GitHub SSH host key to known_hosts"
    echo 'github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoq6lEcdZ8mO8v4ZKFy7v1Z/5vC' >> "/home/${OS_USER}/.ssh/known_hosts"
    chown "${OS_USER}:${OS_USER}" "/home/${OS_USER}/.ssh/known_hosts"
    chmod 0644 "/home/${OS_USER}/.ssh/known_hosts"
    log "SSH keys configured successfully"
    
    # Clean up deploy keys from boot partition for security
    log "Cleaning up deploy keys from boot partition..."
    shred -u /boot/keys/id_ed25519 /boot/keys/id_ed25519.pub 2>/dev/null || true
    rmdir /boot/keys 2>/dev/null || true
    log "Deploy keys cleaned up"
else
    error_exit "/boot/keys/id_ed25519 not found - SSH deploy key is required"
fi

log "Cloning or updating HomeHub repository..."
# Clone or update the repository
if [ ! -d "${APP_DIR}/.git" ]; then
    log "Cloning repository for the first time..."
    sudo -u "${OS_USER}" git clone "${REPO_SSH}" "${APP_DIR}" || error_exit "Failed to clone repository"
    log "Repository cloned successfully to ${APP_DIR}"
else
    log "Repository already exists, updating..."
    (cd "${APP_DIR}" && sudo -u "${OS_USER}" git fetch --all && sudo -u "${OS_USER}" git reset --hard origin/main) || error_exit "Failed to update repository"
    log "Repository updated successfully"
fi

# SSH keys are already cleaned up in the SSH setup section above

log "Pre-pulling Docker images for faster startup..."
# Pre-pull images for each compose project
for rel in "${COMPOSE_STACKS[@]}"; do
    dir="${APP_DIR}/${rel}"
    if [ -f "${dir}/docker-compose.yml" ] || [ -f "${dir}/compose.yml" ]; then
        log "Pre-pulling images for ${rel}..."
        (cd "${dir}" && sudo -u "${OS_USER}" /usr/bin/docker compose pull) || {
            log "Warning: Failed to pre-pull images for ${rel}, continuing..."
        }
    else
        log "Warning: No compose file found in ${dir}, skipping pre-pull"
    fi
done

log "Setting up Portainer container service..."
# Create Portainer data directory
install -d -o "${OS_USER}" -g "${OS_USER}" -m 0755 "${PORTAINER_DATA}" || error_exit "Failed to create Portainer data directory"

# Create Portainer systemd service
cat > /etc/systemd/system/portainer.service << EOF
[Unit]
Description=Portainer CE
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/docker run -d \\
  --name portainer \\
  --restart=always \\
  -p 9000:9000 \\
  -v /var/run/docker.sock:/var/run/docker.sock \\
  -v ${PORTAINER_DATA}:/data \\
  ${PORTAINER_IMAGE}
ExecStop=/usr/bin/docker stop portainer
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload || error_exit "Failed to reload systemd daemon"
systemctl enable portainer.service || error_exit "Failed to enable Portainer service"
log "Portainer service configured and enabled"

log "Setting up HomeHub Docker Compose services..."
# Create service to manage all compose stacks
cat > /etc/systemd/system/homehub-compose.service << EOF
[Unit]
Description=HomeHub Docker Compose stacks
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${APP_DIR}
ExecStart=/bin/bash -lc '
set -euo pipefail
for rel in ${COMPOSE_STACKS[@]}; do
  d="${APP_DIR}/\${rel}"
  if [ -f "\${d}/docker-compose.yml" ] || [ -f "\${d}/compose.yml" ]; then
    echo "[homehub-compose] Starting \${rel}..."
    (cd "\${d}" && /usr/bin/docker compose up -d) || echo "[homehub-compose] Warning: Failed to start \${rel}"
  else
    echo "[homehub-compose] Warning: No compose file found in \${d}"
  fi
done
echo "[homehub-compose] All stacks processed"
'
ExecStop=/bin/bash -lc '
for rel in ${COMPOSE_STACKS[@]}; do
  d="${APP_DIR}/\${rel}"
  if [ -f "\${d}/docker-compose.yml" ] || [ -f "\${d}/compose.yml" ]; then
    echo "[homehub-compose] Stopping \${rel}..."
    (cd "\${d}" && /usr/bin/docker compose down) || echo "[homehub-compose] Warning: Failed to stop \${rel}"
  fi
done
echo "[homehub-compose] All stacks stopped"
'

[Install]
WantedBy=multi-user.target
EOF

systemctl enable homehub-compose.service || error_exit "Failed to enable HomeHub Compose service"
log "HomeHub Compose service configured and enabled"

log "Finalizing first-boot setup..."
# Install and manage the first-boot service
install -m 0644 /boot/firstboot.service /etc/systemd/system/firstboot.service || error_exit "Failed to install firstboot service"
systemctl enable firstboot.service || true
systemctl start firstboot.service || true  # Ensure this run is recorded

# Disable the first-boot service so it won't run again
systemctl disable firstboot.service || true
rm -f /etc/systemd/system/firstboot.service || true
rm -f /usr/local/sbin/firstboot.sh || true

log "=== HomeHub First Boot Provisioning COMPLETED Successfully ==="
log "Services configured:"
log "  ✓ Docker and Docker Compose installed"
log "  ✓ Repository cloned: ${REPO_SSH}"
log "  ✓ Portainer available at http://<pi-ip>:9000"
log "  ✓ HomeHub services will start automatically"
log "  ✓ SSH deploy keys cleaned up"
log "  ✓ First-boot service disabled"
log ""
log "System is ready! All services will start on next reboot."
log "Completed at $(date -Iseconds)"

# Trigger a reboot to ensure all services start fresh
log "Rebooting system to complete setup..."
shutdown -r +1 "HomeHub provisioning complete, rebooting in 1 minute..."