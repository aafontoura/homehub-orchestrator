#!/usr/bin/env bash
set -euo pipefail

# Default OS version to use when not specified
CURRENT_INSTALLED_OS_VERSION="https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2025-05-13/2025-05-13-raspios-bookworm-armhf-lite.img.xz"

# Function to display usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    -i, --image <URL_OR_PATH>    Raspberry Pi OS image URL or local path
                                 (defaults to current installed OS version if not specified)
    -d, --disk <DISK>           Target disk device (REQUIRED, e.g., /dev/disk2)
    -p, --password <PASSWORD>   Plain text password for pi user (REQUIRED)
    -w, --wifi-ssid <SSID>      WiFi network name (SSID) for automatic connection
    -k, --wifi-password <PASS>  WiFi network password
    -c, --wifi-country <CODE>   WiFi country code (e.g., US, GB, DE) - defaults to NL
    -f, --force-download        Force re-download of image even if cached locally
    -h, --help                  Show this help message

EXAMPLES:
    # Use default OS image
    $0 --disk /dev/disk2 --password "mypassword"
    
    # Use specific OS image
    $0 --image https://downloads.raspberrypi.org/raspios_lite_armhf_latest --disk /dev/disk2 --password "mypassword"
    
    # Use local image file
    $0 --image ./my-custom-image.img.xz --disk /dev/disk2 --password "mypassword"
    
    # Force re-download of cached image
    $0 --disk /dev/disk2 --password "mypassword" --force-download
    
    # With WiFi configuration
    $0 --disk /dev/disk2 --password "mypassword" --wifi-ssid "MyNetwork" --wifi-password "wifipass123"
    
    # With WiFi and specific country code
    $0 --disk /dev/disk2 --password "mypassword" --wifi-ssid "MyNetwork" --wifi-password "wifipass123" --wifi-country "GB"

EOF
}

# Initialize variables
IMAGE_SOURCE=""
DISK=""
PLAINTEXT_PASSWORD=""
WIFI_SSID=""
WIFI_PASSWORD=""
WIFI_COUNTRY="NL"  # Default to NL
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

if [[ -z "$PLAINTEXT_PASSWORD" ]]; then
    echo "Error: Password parameter is required."
    echo "Use --password or -p to specify the password for the pi user"
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

# Setup directories
WORK_DIR="/tmp/rpi-image-work"
CACHE_DIR="$HOME/.cache/homehub-orchestrator/images"
MOUNT_POINT="/Volumes/boot"

# Display configuration
echo "=== Raspberry Pi Disk Initialization ==="
echo "Image source: $IMAGE_SOURCE"
echo "Target disk: $DISK"
echo "Username: pi"
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

echo "Flashing $IMG_FILE to $DISK (this may take a while)..."
sudo dd if="$IMG_FILE" of="$DISK" bs=4m conv=sync status=progress
sync

echo "Mounting boot partition..."
BOOT_PARTITION="${DISK}s1"
sudo mkdir -p "$MOUNT_POINT"

# This is a macOS-specific command; it should be simpler in Linux
sudo mount -t msdos -o rw "$BOOT_PARTITION" "$MOUNT_POINT"

echo "Enabling SSH on first boot..."
touch "$MOUNT_POINT/ssh"

# Encrypt the plaintext password
echo "Encrypting the provided plaintext password..."
ENCRYPTED_PASSWORD=$(echo "$PLAINTEXT_PASSWORD" | openssl passwd -6 -stdin)

# Create userconf file with the encrypted password
USERNAME="pi"  # You can modify this to any username you prefer
echo "Creating userconf file with username '$USERNAME' and the encrypted password..."
echo "$USERNAME:$ENCRYPTED_PASSWORD" | sudo tee "$MOUNT_POINT/userconf" > /dev/null

# Configure WiFi if credentials were provided
if [[ -n "$WIFI_SSID" ]]; then
    echo "Configuring WiFi for network '$WIFI_SSID'..."
    
    # Create wpa_supplicant.conf file for WiFi configuration
    sudo tee "$MOUNT_POINT/wpa_supplicant.conf" > /dev/null << EOF
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
else
    echo "No WiFi configuration provided, Pi will require Ethernet connection"
fi

sleep 1

echo "Unmounting boot partition..."
diskutil unmount "$BOOT_PARTITION"

rm -r "$WORK_DIR"

echo "Done! The SD card is flashed, SSH is enabled, and user '$USERNAME' is set up with the provided password."
if [[ -n "$WIFI_SSID" ]]; then
    echo "WiFi is configured for network '$WIFI_SSID'. The Pi will connect automatically on first boot."
else
    echo "No WiFi configured. Connect the Pi via Ethernet cable for network access."
fi