#!/usr/bin/env bash
set -euo pipefail

# Default OS version to use when not specified
CURRENT_INSTALLED_OS_VERSION="https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2025-05-13/2025-05-13-raspios-bookworm-armhf-lite.img.xz"

# Function to display usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

This script is designed for macOS only.

OPTIONS:
    -i, --image <URL_OR_PATH>     Raspberry Pi OS image URL or local path
                                  (defaults to current installed OS version if not specified)
    -d, --disk <DISK>            Target disk device (REQUIRED, e.g., /dev/disk2)
    -p, --password <PASSWORD>    Plain text password for pi user (prompted if not provided)
    --password-hash <HASH>       Pre-hashed password (use either --password or --password-hash)
    -w, --wifi-ssid <SSID>       WiFi network name (SSID) for automatic connection
    -k, --wifi-password <PASS>   WiFi network password
    -c, --wifi-country <CODE>    WiFi country code (e.g., US, GB, DE) - defaults to NL
    -r, --repo-ssh <URL>         SSH URL for your private repo (REQUIRED, e.g., git@github.com:user/repo.git)
    -s, --ssh-key <PATH>         Path to SSH private key for repo access (REQUIRED)
    -u, --os-user <USER>         OS username (defaults to pi)
    --portainer-version <VER>    Portainer version (defaults to 2.25.1)
    -f, --force-download         Force re-download of image even if cached locally
    -h, --help                   Show this help message

EXAMPLES:
    # Basic setup with GitHub repo and SSH key
    $0 --disk /dev/disk2 --password "mypassword" \\
       --repo-ssh "git@github.com:user/homehub.git" \\
       --ssh-key ~/.ssh/id_ed25519_deploy
    
    # With WiFi configuration
    $0 --disk /dev/disk2 --password "mypassword" \\
       --wifi-ssid "MyNetwork" --wifi-password "wifipass123" \\
       --repo-ssh "git@github.com:user/homehub.git" \\
       --ssh-key ~/.ssh/id_ed25519_deploy
    
    # With pre-hashed password (more secure)
    $0 --disk /dev/disk2 --password-hash "\$6\$..." \\
       --repo-ssh "git@github.com:user/homehub.git" \\
       --ssh-key ~/.ssh/id_ed25519_deploy
    
    # With custom OS user and specific versions
    $0 --disk /dev/disk2 --password "mypassword" \\
       --os-user "homehub" --portainer-version "2.26.0" \\
       --repo-ssh "git@github.com:user/homehub.git" \\
       --ssh-key ~/.ssh/id_ed25519_deploy

EOF
}

# Initialize variables
IMAGE_SOURCE=""
DISK=""
PLAINTEXT_PASSWORD=""
PASSWORD_HASH=""
WIFI_SSID=""
WIFI_PASSWORD=""
WIFI_COUNTRY="NL"  # Default to NL
REPO_SSH="git@github.com:aafontoura/homehub-orchestrator.git"
SSH_KEY_PATH=""
OS_USER="pi"  # Default to pi
PORTAINER_VERSION="2.25.1"  # Default version (multi-arch)
FORCE_DOWNLOAD=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--image)
            IMAGE_SOURCE="$2"
            shift 2
            ;;
        -d|--disk)
            DISK="$2"
            shift 2
            ;;
        -p|--password)
            PLAINTEXT_PASSWORD="$2"
            shift 2
            ;;
        -w|--wifi-ssid)
            WIFI_SSID="$2"
            shift 2
            ;;
        -k|--wifi-password)
            WIFI_PASSWORD="$2"
            shift 2
            ;;
        -c|--wifi-country)
            WIFI_COUNTRY="$2"
            shift 2
            ;;
        -r|--repo-ssh)
            REPO_SSH="$2"
            shift 2
            ;;
        -s|--ssh-key)
            SSH_KEY_PATH="$2"
            shift 2
            ;;
        -u|--os-user)
            OS_USER="$2"
            shift 2
            ;;
        --portainer-version)
            PORTAINER_VERSION="$2"
            shift 2
            ;;
        --password-hash)
            PASSWORD_HASH="$2"
            shift 2
            ;;
        -f|--force-download)
            FORCE_DOWNLOAD=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Error: Unknown option $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$DISK" ]]; then
    echo "Error: Disk parameter is required and must be explicitly specified."
    echo "Use --disk or -d to specify the target disk (e.g., /dev/disk2)"
    echo ""
    show_usage
    exit 1
fi

# Handle password input
if [[ -n "$PLAINTEXT_PASSWORD" && -n "$PASSWORD_HASH" ]]; then
    echo "Error: Use either --password or --password-hash, not both."
    echo ""
    show_usage
    exit 1
fi

if [[ -z "$PLAINTEXT_PASSWORD" && -z "$PASSWORD_HASH" ]]; then
    read -rsp "Password for $OS_USER: " PLAINTEXT_PASSWORD
    echo
fi

if [[ -z "$PLAINTEXT_PASSWORD" && -z "$PASSWORD_HASH" ]]; then
    echo "Error: Password is required."
    echo "Use --password or -p to specify the password, or --password-hash for pre-hashed password"
    echo ""
    show_usage
    exit 1
fi

# if [[ -z "$REPO_SSH" ]]; then
#     echo "Error: Repository SSH URL is required."
#     echo "Use --repo-ssh or -r to specify the SSH URL for your private repo (e.g., git@github.com:user/repo.git)"
#     echo ""
#     show_usage
#     exit 1
# fi

if [[ -z "$SSH_KEY_PATH" ]]; then
    echo "Error: SSH key path is required."
    echo "Use --ssh-key or -s to specify the path to your SSH private key for repo access"
    echo ""
    show_usage
    exit 1
fi

if [[ ! -f "$SSH_KEY_PATH" ]]; then
    echo "Error: SSH key file not found: $SSH_KEY_PATH"
    echo "Please ensure the SSH key file exists and is accessible"
    echo ""
    show_usage
    exit 1
fi

# Validate WiFi parameters (if one is provided, both should be provided)
if [[ -n "$WIFI_SSID" ]] && [[ -z "$WIFI_PASSWORD" ]]; then
    echo "Error: WiFi SSID provided but WiFi password is missing."
    echo "Use --wifi-password or -k to specify the WiFi password"
    echo ""
    show_usage
    exit 1
fi

if [[ -z "$WIFI_SSID" ]] && [[ -n "$WIFI_PASSWORD" ]]; then
    echo "Error: WiFi password provided but WiFi SSID is missing."
    echo "Use --wifi-ssid or -w to specify the WiFi network name"
    echo ""
    show_usage
    exit 1
fi

# Use default OS image if not specified
if [[ -z "$IMAGE_SOURCE" ]]; then
    echo "No image specified, using current installed OS version:"
    echo "$CURRENT_INSTALLED_OS_VERSION"
    IMAGE_SOURCE="$CURRENT_INSTALLED_OS_VERSION"
fi

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)." >&2
    exit 1
fi

# Prerequisite checks (macOS only)
need() { command -v "$1" >/dev/null || { echo "Error: Missing required tool: $1"; exit 1; }; }
need curl
need xz
need openssl
need dd
need diskutil
need file

# Setup directories
WORK_DIR="/tmp/rpi-image-work"
CACHE_DIR="$HOME/.cache/homehub-orchestrator/images"

# Cleanup function
cleanup() {
    sync || true
    
    rm -rf "$WORK_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# Display configuration
echo "=== Raspberry Pi Disk Initialization ==="
echo "Image source: $IMAGE_SOURCE"
echo "Target disk: $DISK"
echo "OS Username: $OS_USER"
echo "Repository SSH: $REPO_SSH"
echo "SSH Key: $SSH_KEY_PATH"
echo "Portainer Version: $PORTAINER_VERSION"
if [[ -n "$WIFI_SSID" ]]; then
    echo "WiFi SSID: $WIFI_SSID"
    echo "WiFi Country: $WIFI_COUNTRY"
    echo "WiFi Password: [HIDDEN]"
else
    echo "WiFi: Not configured"
fi
echo "Cache directory: $CACHE_DIR"
if [[ "$FORCE_DOWNLOAD" == true ]]; then
    echo "Force download: YES"
fi
echo "=========================================="
echo ""

# Function to create firstboot.service systemd unit
create_firstboot_service() {
    local mount_point="$1"
    cat > "$mount_point/firstboot.service" << 'EOF'
[Unit]
Description=One-time provisioning on first boot
After=network-online.target
Wants=network-online.target
ConditionPathExists=/boot/firstboot.sh

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/firstboot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
}

# Function to create customized firstboot.sh provisioning script
create_firstboot_script() {
    local mount_point="$1"
    local os_user="$2"
    local repo_ssh="$3"
    local portainer_version="$4"
    local script_dir="$(dirname "${BASH_SOURCE[0]}")"
    
    # Check if the firstboot.sh template exists
    if [[ ! -f "$script_dir/firstboot.sh" ]]; then
        echo "Error: firstboot.sh template not found at $script_dir/firstboot.sh"
        exit 1
    fi
    
    echo "Copying and customizing firstboot.sh template..."
    
    # Copy the template and replace placeholders
    sed \
        -e "s/__OS_USER__/$os_user/g" \
        -e "s|__REPO_SSH__|$repo_ssh|g" \
        -e "s/__PORTAINER_VERSION__/$portainer_version/g" \
        "$script_dir/firstboot.sh" > "$mount_point/firstboot.sh"
    
    chmod +x "$mount_point/firstboot.sh"
    echo "FirstBoot script customized and copied to boot partition"
}

# Validate that the firstboot.sh template exists
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
if [[ ! -f "$SCRIPT_DIR/firstboot.sh" ]]; then
    echo "Error: firstboot.sh template not found at $SCRIPT_DIR/firstboot.sh"
    echo "This template file is required for the first-boot provisioning system."
    exit 1
fi

echo "Creating work directory at $WORK_DIR"
mkdir -p "$WORK_DIR"
mkdir -p "$CACHE_DIR"

# Function to generate cache filename from URL
generate_cache_filename() {
    local url="$1"
    # Extract filename from URL, or create hash-based name if not available
    local filename=$(basename "$url")
    if [[ "$filename" == *".img.xz" ]] || [[ "$filename" == *".zip" ]]; then
        echo "$filename"
    else
        # Create a hash-based filename for URLs without clear filenames
        local hash=$(echo -n "$url" | shasum -a 256 | cut -d' ' -f1)
        echo "rpi-image-${hash:0:16}.img.xz"
    fi
}

# Function to download official SHA256 checksum
download_official_checksum() {
    local url="$1"
    local checksum_file="$2"
    local checksum_url="${url}.sha256"
    
    echo "Downloading official SHA256 checksum from: $checksum_url"
    
    # Try to download the official checksum file
    if curl -L --fail --silent --show-error "$checksum_url" -o "$checksum_file"; then
        echo "Official checksum downloaded successfully"
        return 0
    else
        echo "Warning: Could not download official checksum from $checksum_url"
        echo "This may be normal if the source doesn't provide SHA256 files"
        return 1
    fi
}

# Function to validate cache file integrity
validate_cache_integrity() {
    local cached_file="$1"
    local url="$2"
    
    echo "Validating cache integrity..."
    
    # Check if file exists and is not empty
    if [[ ! -f "$cached_file" ]]; then
        echo "Cache validation failed: File does not exist"
        return 1
    fi
    
    if [[ ! -s "$cached_file" ]]; then
        echo "Cache validation failed: File is empty"
        return 1
    fi
    
    # Check file size (minimum reasonable size for a Raspberry Pi OS image)
    local file_size=$(stat -f%z "$cached_file" 2>/dev/null || stat -c%s "$cached_file" 2>/dev/null)
    local min_size=$((100 * 1024 * 1024))  # 100MB minimum
    
    if [[ "$file_size" -lt "$min_size" ]]; then
        echo "Cache validation failed: File too small (${file_size} bytes, minimum ${min_size} bytes)"
        return 1
    fi
    
    # Check if file appears to be a valid compressed file by examining magic bytes
    local file_type=$(file -b "$cached_file")
    if [[ ! "$file_type" =~ (XZ|xz|gzip|ZIP|zip) ]]; then
        echo "Cache validation failed: File does not appear to be a valid compressed image ($file_type)"
        return 1
    fi
    
    # Validate against official checksum
    local checksum_file="${cached_file}.sha256"
    local current_checksum=$(shasum -a 256 "$cached_file" | cut -d' ' -f1)
    
    # Always try to download the official checksum for validation
    if [[ "$url" =~ ^http ]] && download_official_checksum "$url" "$checksum_file"; then
        # Parse the checksum file (handle different formats)
        local expected_checksum
        if [[ -f "$checksum_file" ]]; then
            # Try different common formats of SHA256 files
            # Format 1: "checksum filename" (most common)
            expected_checksum=$(head -n 1 "$checksum_file" | awk '{print $1}')
            
            # Format 2: "checksum  filename" (with two spaces)
            if [[ -z "$expected_checksum" ]] || [[ ${#expected_checksum} -ne 64 ]]; then
                expected_checksum=$(head -n 1 "$checksum_file" | cut -d' ' -f1)
            fi
            
            # Validate checksum format (should be 64 hex characters)
            if [[ ${#expected_checksum} -eq 64 ]] && [[ "$expected_checksum" =~ ^[a-fA-F0-9]+$ ]]; then
                if [[ "$current_checksum" == "$expected_checksum" ]]; then
                    echo "Cache validation passed: Official checksum verified"
                    return 0
                else
                    echo "Cache validation failed: Official checksum mismatch"
                    echo "  Expected: $expected_checksum"
                    echo "  Actual:   $current_checksum"
                    return 1
                fi
            else
                echo "Warning: Invalid checksum format in official file, falling back to basic validation"
            fi
        fi
    fi
    
    # Fallback: If no official checksum available, just do basic validation
    echo "Cache validation passed: Basic validation completed (no official checksum available)"
    return 0
}

# Function to cleanup corrupted cache
cleanup_corrupted_cache() {
    local cached_file="$1"
    local checksum_file="${cached_file}.sha256"
    
    echo "Removing corrupted cache files..."
    rm -f "$cached_file" "$checksum_file"
    echo "Cache cleaned, will re-download with fresh official checksum"
}

# Handle image source (URL or local file)
if [[ "$IMAGE_SOURCE" =~ ^http ]]; then
    # Generate cache filename
    CACHE_FILENAME=$(generate_cache_filename "$IMAGE_SOURCE")
    CACHED_FILE="$CACHE_DIR/$CACHE_FILENAME"
    
    # Check if we should use cached version
    if [[ -f "$CACHED_FILE" ]] && [[ "$FORCE_DOWNLOAD" == false ]]; then
        echo "Found cached image: $CACHED_FILE"
        
        # Validate cache integrity before use
        if validate_cache_integrity "$CACHED_FILE" "$IMAGE_SOURCE"; then
            echo "Using validated cached version (use --force-download to re-download)"
            cp "$CACHED_FILE" "$WORK_DIR/rpi_image.img.xz"
        else
            echo "Cache validation failed, removing corrupted cache and re-downloading..."
            cleanup_corrupted_cache "$CACHED_FILE"
            # Fall through to download section
        fi
    fi
    
    # Download if no valid cache exists or force download requested
    if [[ ! -f "$WORK_DIR/rpi_image.img.xz" ]]; then
        if [[ "$FORCE_DOWNLOAD" == true ]] && [[ -f "$CACHED_FILE" ]]; then
            echo "Force download requested, removing cached file..."
            rm "$CACHED_FILE"
        fi
        
        echo "Downloading Raspberry Pi OS image from: $IMAGE_SOURCE"
        echo "This may take several minutes depending on your internet connection..."
        
        # Download to temporary location first
        TEMP_DOWNLOAD="$CACHE_DIR/temp_download_$$"
        if curl -L --fail --show-error --progress-bar "$IMAGE_SOURCE" -o "$TEMP_DOWNLOAD"; then
            # Validate downloaded file before caching
            echo "Validating downloaded file..."
            file_size=$(stat -f%z "$TEMP_DOWNLOAD" 2>/dev/null || stat -c%s "$TEMP_DOWNLOAD" 2>/dev/null)
            min_size=$((100 * 1024 * 1024))  # 100MB minimum
            
            if [[ "$file_size" -lt "$min_size" ]]; then
                echo "Error: Downloaded file too small (${file_size} bytes), download may have failed"
                rm -f "$TEMP_DOWNLOAD"
                exit 1
            fi
            
            # Move to cache location on successful download
            mv "$TEMP_DOWNLOAD" "$CACHED_FILE"
            
            # Download and store official checksum for future validation
            checksum_file="${CACHED_FILE}.sha256"
            if download_official_checksum "$IMAGE_SOURCE" "$checksum_file"; then
                echo "Official checksum downloaded and stored for future validation"
            else
                echo "No official checksum available, basic validation will be used"
            fi
            
            echo "Image cached at: $CACHED_FILE"
            cp "$CACHED_FILE" "$WORK_DIR/rpi_image.img.xz"
        else
            echo "Error: Failed to download image from $IMAGE_SOURCE"
            rm -f "$TEMP_DOWNLOAD"
            exit 1
        fi
    fi
else
    echo "Using local image file: $IMAGE_SOURCE"
    if [[ ! -f "$IMAGE_SOURCE" ]]; then
        echo "Error: Local image file not found: $IMAGE_SOURCE"
        exit 1
    fi
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

# Refuse to write to the system disk (macOS only)
SYS_DISK="$(diskutil info / | awk -F': *' '/Parent Whole Disk/{print $2}')"
if [[ -n "$SYS_DISK" && "/dev/$SYS_DISK" == "$DISK" ]]; then
  echo "Error: $DISK appears to be the system disk. Aborting."; exit 1
fi

echo "Flashing $IMG_FILE to $DISK (this may take a while)..."
# macOS: use raw device for speed, no status=progress
TARGET="${DISK/disk/rdisk}"
sudo dd if="$IMG_FILE" of="$TARGET" bs=8m conv=sync
sync

echo "Identifying partitions..."
# Identify boot and root partitions (macOS only)
BOOT_PARTITION="${DISK}s1"
ROOT_PARTITION="${DISK}s2"

# Verify partitions exist
if ! diskutil list "$DISK" | grep -q "$(basename "${DISK}")s1" ; then
    echo "Error: Boot partition not found on $DISK"
    exit 1
fi
if ! diskutil list "$DISK" | grep -q "$(basename "${DISK}")s2"; then
    echo "Error: Root partition not found on $DISK"
    exit 1
fi

echo "Boot partition: $BOOT_PARTITION"
echo "Root partition: $ROOT_PARTITION"



# Mount boot partition (macOS only)
echo "Mounting boot partition..."
diskutil mount "$BOOT_PARTITION" >/dev/null
BOOT_VOL_PATH="$(diskutil info "$BOOT_PARTITION" | awk -F': *' '/Mount Point/{print $2}')"
[[ -z "$BOOT_VOL_PATH" || "$BOOT_VOL_PATH" == "Not mounted" ]] && { echo "Failed to mount boot"; exit 1; }
# Either write to $BOOT_VOL_PATH directly, or bind it to your temp mount

echo "Enabling SSH on first boot..."
touch "$BOOT_VOL_PATH/ssh"

# Handle password encryption
if [[ -n "$PASSWORD_HASH" ]]; then
    ENCRYPTED_PASSWORD="$PASSWORD_HASH"
    echo "Using provided password hash"
else
    echo "Encrypting the provided plaintext password..."
    ENCRYPTED_PASSWORD=$(echo "$PLAINTEXT_PASSWORD" | openssl passwd -6 -stdin)
fi

# Create userconf file with the encrypted password
echo "Creating userconf file with username '$OS_USER' and the encrypted password..."
echo "$OS_USER:$ENCRYPTED_PASSWORD" | sudo tee "$BOOT_VOL_PATH/userconf" > /dev/null

# Configure WiFi if credentials were provided
if [[ -n "$WIFI_SSID" ]]; then
    echo "Configuring WiFi for network '$WIFI_SSID'..."
    
    # Generate UUID for NetworkManager connection
    CONNECTION_UUID=$(uuidgen 2>/dev/null || echo "550e8400-e29b-41d4-a716-446655440000")
    CONNECTION_ID="HomeHub-WiFi"
    
    # Create NetworkManager config in boot partition (macOS only)
    # The firstboot script will handle the installation
    sudo mkdir -p "$BOOT_VOL_PATH/network"
    
    # Create the NetworkManager connection file
    sudo tee "$BOOT_VOL_PATH/network/wifi-connection.nmconnection" > /dev/null << EOF
[connection]
id=${CONNECTION_ID}
uuid=${CONNECTION_UUID}
type=wifi
autoconnect=true
autoconnect-priority=100

[wifi]
mode=infrastructure
ssid=${WIFI_SSID}
band=bg
channel=0

[wifi-security]
auth-alg=open
key-mgmt=wpa-psk
psk=${WIFI_PASSWORD}

[ipv4]
method=auto
dns=8.8.8.8;8.8.4.4;

[ipv6]
addr-gen-mode=stable-privacy
method=auto
EOF
    
    # Also create the legacy wpa_supplicant.conf as fallback for older images
    sudo tee "$BOOT_VOL_PATH/wpa_supplicant.conf" > /dev/null << EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=$WIFI_COUNTRY

network={
    ssid="$WIFI_SSID"
    psk="$WIFI_PASSWORD"
    key_mgmt=WPA-PSK
}
EOF
    
    echo "WiFi configuration created for network '$WIFI_SSID' with country code '$WIFI_COUNTRY'"
    echo "Using boot partition NetworkManager config (will be installed by firstboot script)"
else
    echo "No WiFi configuration provided, Pi will require Ethernet connection"
fi

# Setup first-boot execution (macOS only)
echo "Setting up first-boot execution..."
# Append systemd.run to cmdline.txt for one-time execution
CMDLINE="$BOOT_VOL_PATH/cmdline.txt"
if [[ -f "$CMDLINE" ]]; then
    # Add systemd.run parameters to cmdline.txt (only if not already present)
    if ! grep -q 'systemd.run=/boot/firstboot.sh' "$CMDLINE"; then
        sudo sed -i '' -e 's/$/ systemd.run=\/boot\/firstboot.sh systemd.run_success_action=reboot systemd.run_failure_action=emergency/' "$CMDLINE"
        echo "Added systemd.run to cmdline.txt for first-boot execution"
    else
        echo "systemd.run already present in cmdline.txt"
    fi
else
    echo "Warning: cmdline.txt not found, first-boot may not execute"
fi

# Create systemd first-boot files
echo "Creating systemd first-boot service and script..."
create_firstboot_service "$BOOT_VOL_PATH"
create_firstboot_script "$BOOT_VOL_PATH" "$OS_USER" "$REPO_SSH" "$PORTAINER_VERSION"

# Setup SSH deploy key
echo "Setting up SSH deploy key for repository access..."
sudo mkdir -p "$BOOT_VOL_PATH/keys"
sudo cp "$SSH_KEY_PATH" "$BOOT_VOL_PATH/keys/id_ed25519"
if [[ -f "${SSH_KEY_PATH}.pub" ]]; then
    sudo cp "${SSH_KEY_PATH}.pub" "$BOOT_VOL_PATH/keys/id_ed25519.pub"
else
    echo "Warning: Public key file ${SSH_KEY_PATH}.pub not found"
    echo "Generating public key from private key..."
    ssh-keygen -y -f "$SSH_KEY_PATH" | sudo tee "$BOOT_VOL_PATH/keys/id_ed25519.pub" > /dev/null
fi

# Set appropriate permissions for the keys
sudo chmod 600 "$BOOT_VOL_PATH/keys/id_ed25519"
sudo chmod 644 "$BOOT_VOL_PATH/keys/id_ed25519.pub"

echo "First-boot provisioning system configured successfully!"
echo "Template used: scripts/firstboot.sh"
echo "The Pi will automatically:"
echo "  - Install Docker and Docker Compose"
echo "  - Clone your repository: $REPO_SSH"
echo "  - Pre-pull Docker images for faster startup"
echo "  - Setup Portainer on port 9000"
echo "  - Start all HomeHub services automatically"
echo "  - Clean up deploy keys after setup"

sleep 1

echo "Unmounting boot partition..."
diskutil unmount "$BOOT_PARTITION" || true

# Cleanup is handled by trap

echo "=== Setup Complete! ==="
echo "The SD card is ready with:"
echo "  ✓ Raspberry Pi OS flashed"
echo "  ✓ SSH enabled"
echo "  ✓ User '$OS_USER' configured"
echo "  ✓ SystemD first-boot provisioning system installed"
echo "  ✓ Deploy SSH key for repository access"
if [[ -n "$WIFI_SSID" ]]; then
    echo "  ✓ WiFi configured for network '$WIFI_SSID'"
else
    echo "  ! WiFi not configured - Ethernet connection required"
fi
echo ""
echo "On first boot, the Pi will automatically:"
echo "  1. Connect to internet (WiFi or Ethernet)"
echo "  2. Install Docker and Docker Compose v2"
echo "  3. Clone your repository: $REPO_SSH"
echo "  4. Setup Portainer web interface (port 9000)"
echo "  5. Start all HomeHub Docker services"
echo "  6. Clean up deploy keys for security"
echo ""
echo "Monitor progress: ssh $OS_USER@<pi-ip> 'tail -f /var/log/firstboot.log'"
echo "Access Portainer: http://<pi-ip>:9000"
echo "HomeHub services will be available on their configured ports"