#!/bin/bash
#
# create-usb.sh - Create Ubuntu 24.04 Autoinstall USB with TPM2 encryption
#
# This script downloads the Ubuntu 24.04 Server ISO, modifies it to include
# autoinstall configuration with TPM2-based full disk encryption, and creates
# a bootable USB installer.
#
# Requirements:
#   - xorriso (for ISO manipulation)
#   - curl or wget (for ISO download)
#   - openssl (for generating random passwords)
#   - sudo (for mounting ISOs and writing to USB)
#

set -e

# Configuration defaults
UBUNTU_VERSION="24.04"
UBUNTU_ISO_URL="https://releases.ubuntu.com/${UBUNTU_VERSION}.1/ubuntu-${UBUNTU_VERSION}.1-live-server-amd64.iso"
ISO_NAME="ubuntu-${UBUNTU_VERSION}.1-live-server-amd64.iso"
OUTPUT_ISO="ubuntu-${UBUNTU_VERSION}-autoinstall-tpm2.iso"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$SCRIPT_DIR/build"
ISO_EXTRACT_DIR="$WORK_DIR/iso-extract"
ISO_MOUNT_DIR="$WORK_DIR/iso-mount"

# Command-line option defaults
SKIP_DOWNLOAD=false
AUTO_USB_WRITE=false
USB_DEVICE=""
QUIET=false
CLEANUP_BUILD=false
USER_DATA_FILE="$SCRIPT_DIR/user-data"
META_DATA_FILE="$SCRIPT_DIR/meta-data"
CUSTOM_PASSWORD=""
SKIP_USB_PROMPT=false

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
print_header() {
    if [ "$QUIET" = false ]; then
        echo ""
        echo "========================================="
        echo "$1"
        echo "========================================="
        echo ""
    fi
}

print_success() {
    if [ "$QUIET" = false ]; then
        echo -e "${GREEN}✓${NC} $1"
    fi
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    if [ "$QUIET" = false ]; then
        echo "$1"
    fi
}

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Create a bootable Ubuntu 24.04 USB installer with TPM2 full disk encryption.

OPTIONS:
    -h, --help              Show this help message and exit
    -i, --iso-path PATH     Use existing ISO at PATH instead of downloading
    -o, --output PATH       Output ISO path (default: $OUTPUT_ISO)
    -u, --usb DEVICE        Automatically write to USB device (e.g., sdb or /dev/sdb)
    -w, --write-usb         Prompt for USB device and write after ISO creation
    -s, --skip-usb          Skip USB writing prompt (only create ISO)
    -p, --password PASS     Use custom temporary password instead of generating one
    -c, --config-dir DIR    Directory containing user-data and meta-data files
    -q, --quiet             Suppress non-essential output
    --cleanup               Remove build directory after successful ISO creation
    --iso-url URL           Use custom ISO download URL
    --version VERSION       Ubuntu version to use (default: 24.04)

EXAMPLES:
    # Basic usage - create ISO and prompt for USB writing
    $(basename "$0")

    # Use existing ISO file
    $(basename "$0") -i /path/to/ubuntu-24.04-live-server-amd64.iso

    # Create ISO and automatically write to /dev/sdb
    $(basename "$0") -u sdb

    # Create ISO only, skip USB writing
    $(basename "$0") -s -o my-custom.iso

    # Use custom config directory and password
    $(basename "$0") -c ./configs -p MyCustomPassword123

    # Quiet mode with automatic USB writing
    $(basename "$0") -q -u sdb

NOTES:
    - Root/sudo privileges required for mounting ISOs and writing USB
    - Target USB device will be completely erased
    - TPM 2.0 and Secure Boot must be enabled in BIOS for auto-unlock
    - Recovery password will be generated at /root/recovery-password.txt after install

For more information, see README.md or CLAUDE.md

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -i|--iso-path)
                if [ -z "$2" ] || [[ "$2" == -* ]]; then
                    print_error "Error: --iso-path requires a file path"
                    exit 1
                fi
                ISO_NAME="$2"
                SKIP_DOWNLOAD=true
                shift 2
                ;;
            -o|--output)
                if [ -z "$2" ] || [[ "$2" == -* ]]; then
                    print_error "Error: --output requires a file path"
                    exit 1
                fi
                OUTPUT_ISO="$2"
                shift 2
                ;;
            -u|--usb)
                if [ -z "$2" ] || [[ "$2" == -* ]]; then
                    print_error "Error: --usb requires a device name"
                    exit 1
                fi
                USB_DEVICE="$2"
                AUTO_USB_WRITE=true
                SKIP_USB_PROMPT=true
                shift 2
                ;;
            -w|--write-usb)
                AUTO_USB_WRITE=true
                shift
                ;;
            -s|--skip-usb)
                SKIP_USB_PROMPT=true
                shift
                ;;
            -p|--password)
                if [ -z "$2" ] || [[ "$2" == -* ]]; then
                    print_error "Error: --password requires a password value"
                    exit 1
                fi
                CUSTOM_PASSWORD="$2"
                shift 2
                ;;
            -c|--config-dir)
                if [ -z "$2" ] || [[ "$2" == -* ]]; then
                    print_error "Error: --config-dir requires a directory path"
                    exit 1
                fi
                USER_DATA_FILE="$2/user-data"
                META_DATA_FILE="$2/meta-data"
                shift 2
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            --cleanup)
                CLEANUP_BUILD=true
                shift
                ;;
            --iso-url)
                if [ -z "$2" ] || [[ "$2" == -* ]]; then
                    print_error "Error: --iso-url requires a URL"
                    exit 1
                fi
                UBUNTU_ISO_URL="$2"
                shift 2
                ;;
            --version)
                if [ -z "$2" ] || [[ "$2" == -* ]]; then
                    print_error "Error: --version requires a version number"
                    exit 1
                fi
                UBUNTU_VERSION="$2"
                UBUNTU_ISO_URL="https://releases.ubuntu.com/${UBUNTU_VERSION}.1/ubuntu-${UBUNTU_VERSION}.1-live-server-amd64.iso"
                ISO_NAME="ubuntu-${UBUNTU_VERSION}.1-live-server-amd64.iso"
                OUTPUT_ISO="ubuntu-${UBUNTU_VERSION}-autoinstall-tpm2.iso"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

cleanup() {
    print_info ""
    print_info "Cleaning up..."
    if mountpoint -q "$ISO_MOUNT_DIR" 2>/dev/null; then
        sudo umount "$ISO_MOUNT_DIR" || true
    fi

    if [ "$CLEANUP_BUILD" = true ] && [ -d "$WORK_DIR" ]; then
        print_info "Removing build directory..."
        rm -rf "$WORK_DIR"
    else
        print_info "Build artifacts left in: $WORK_DIR"
    fi
}

trap cleanup EXIT

# Validate configuration files
validate_config_files() {
    if [ ! -f "$USER_DATA_FILE" ]; then
        print_error "user-data file not found: $USER_DATA_FILE"
        exit 1
    fi

    if [ ! -f "$META_DATA_FILE" ]; then
        print_error "meta-data file not found: $META_DATA_FILE"
        exit 1
    fi

    print_success "Configuration files found"
}

# Main script
parse_arguments "$@"

print_header "Ubuntu 24.04 TPM2 Autoinstall USB Creator"

# Validate configuration files
validate_config_files

# Check dependencies
print_info "Checking dependencies..."
MISSING_DEPS=0

if ! command -v xorriso &> /dev/null; then
    print_error "xorriso not found. Install with: apt install xorriso"
    MISSING_DEPS=1
fi

if ! command -v openssl &> /dev/null; then
    print_error "openssl not found. Install with: apt install openssl"
    MISSING_DEPS=1
fi

if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
    print_error "curl or wget not found. Install with: apt install curl"
    MISSING_DEPS=1
fi

if [ $MISSING_DEPS -eq 1 ]; then
    print_error "Missing required dependencies. Please install them and try again."
    exit 1
fi

print_success "All dependencies found"

# Create work directories
print_info ""
print_info "Setting up work directories..."
mkdir -p "$WORK_DIR"
mkdir -p "$ISO_MOUNT_DIR"
print_success "Work directories created"

# Download ISO if not present
print_info ""
if [ "$SKIP_DOWNLOAD" = false ]; then
    if [ ! -f "$SCRIPT_DIR/$ISO_NAME" ]; then
        print_warning "Ubuntu ISO not found. Downloading..."
        print_info "URL: $UBUNTU_ISO_URL"
        print_info "This may take a while depending on your connection..."
        print_info ""

        if command -v curl &> /dev/null; then
            curl -L -o "$SCRIPT_DIR/$ISO_NAME" "$UBUNTU_ISO_URL"
        else
            wget -O "$SCRIPT_DIR/$ISO_NAME" "$UBUNTU_ISO_URL"
        fi

        print_success "ISO downloaded"
    else
        print_success "ISO already present: $ISO_NAME"
    fi
else
    # Validate provided ISO path
    if [ ! -f "$ISO_NAME" ]; then
        print_error "ISO file not found: $ISO_NAME"
        exit 1
    fi
    print_success "Using provided ISO: $ISO_NAME"
fi

# Generate or use custom temporary password
print_info ""
if [ -n "$CUSTOM_PASSWORD" ]; then
    TEMP_PASSWORD="$CUSTOM_PASSWORD"
    print_success "Using custom temporary password"
    if [ "$QUIET" = false ]; then
        echo "Password: $TEMP_PASSWORD"
    fi
else
    print_info "Generating temporary LUKS password..."
    TEMP_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')
    print_success "Temporary password generated (will be replaced by TPM2 enrollment)"
    if [ "$QUIET" = false ]; then
        echo "Password: $TEMP_PASSWORD"
    fi
fi

# Mount ISO
print_info ""
print_info "Mounting ISO..."
# Handle both absolute and relative paths
if [[ "$ISO_NAME" = /* ]]; then
    ISO_PATH="$ISO_NAME"
else
    ISO_PATH="$SCRIPT_DIR/$ISO_NAME"
fi
sudo mount -o loop "$ISO_PATH" "$ISO_MOUNT_DIR"
print_success "ISO mounted at $ISO_MOUNT_DIR"

# Extract ISO contents
print_info ""
print_info "Extracting ISO contents..."
print_info "This may take a few minutes..."
rm -rf "$ISO_EXTRACT_DIR"
mkdir -p "$ISO_EXTRACT_DIR"

# Copy all files from ISO
sudo cp -rT "$ISO_MOUNT_DIR" "$ISO_EXTRACT_DIR"

# Fix permissions
sudo chown -R $(id -un):$(id -gn) "$ISO_EXTRACT_DIR"
sudo chmod -R u+w "$ISO_EXTRACT_DIR"

print_success "ISO contents extracted"

# Unmount ISO
sudo umount "$ISO_MOUNT_DIR"

# Create nocloud directory for autoinstall
print_info ""
print_info "Creating autoinstall configuration..."
mkdir -p "$ISO_EXTRACT_DIR/nocloud"

# Copy and modify user-data with temporary password
cp "$USER_DATA_FILE" "$ISO_EXTRACT_DIR/nocloud/user-data"
sed -i "s|TEMP_PASSWORD_REPLACE_ME|$TEMP_PASSWORD|g" "$ISO_EXTRACT_DIR/nocloud/user-data"

# Copy meta-data
cp "$META_DATA_FILE" "$ISO_EXTRACT_DIR/nocloud/meta-data"

print_success "Autoinstall configuration added"

# Modify GRUB configuration
print_info ""
print_info "Modifying GRUB bootloader configuration..."

# Find the GRUB config file
GRUB_CFG="$ISO_EXTRACT_DIR/boot/grub/grub.cfg"

if [ ! -f "$GRUB_CFG" ]; then
    print_error "GRUB config not found at expected location"
    exit 1
fi

# Backup original
cp "$GRUB_CFG" "$GRUB_CFG.backup"

# Add autoinstall parameters to the first menuentry
# Find the first menuentry and add autoinstall parameters
sed -i '0,/linux.*\/casper\/vmlinuz/s|linux.*\/casper\/vmlinuz.*|linux   /casper/vmlinuz autoinstall ds=nocloud;s=/cdrom/nocloud/ quiet splash ---|' "$GRUB_CFG"

# Also modify the timeout to make autoinstall start automatically
sed -i 's/set timeout=.*/set timeout=5/' "$GRUB_CFG" || true

print_success "GRUB configuration modified"

# Rebuild ISO
print_info ""
print_header "Building Custom ISO"

print_info "This may take several minutes..."
print_info ""

# Handle both absolute and relative paths for output
if [[ "$OUTPUT_ISO" = /* ]]; then
    OUTPUT_PATH="$OUTPUT_ISO"
else
    OUTPUT_PATH="$SCRIPT_DIR/$OUTPUT_ISO"
fi

# Build the ISO with xorriso
if [ "$QUIET" = true ]; then
    xorriso -as mkisofs \
        -r -V "Ubuntu Autoinstall TPM2" \
        -o "$OUTPUT_PATH" \
        -J -joliet-long \
        -b boot/grub/i386-pc/eltorito.img \
        -c boot.catalog \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e boot/grub/efi.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        # -isohybrid-apm-hfsplus \
        "$ISO_EXTRACT_DIR" > /dev/null 2>&1
else
    xorriso -as mkisofs \
        -r -V "Ubuntu Autoinstall TPM2" \
        -o "$OUTPUT_PATH" \
        -J -joliet-long \
        -b boot/grub/i386-pc/eltorito.img \
        -c boot.catalog \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e boot/grub/efi.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        # -isohybrid-apm-hfsplus \
        "$ISO_EXTRACT_DIR" 2>&1 | grep -v "^xorriso" | grep -v "^libisofs" || true
fi

if [ $? -eq 0 ] && [ -f "$OUTPUT_PATH" ]; then
    print_success "ISO created successfully!"
    print_info ""
    echo "Output ISO: $OUTPUT_PATH"
    ISO_SIZE=$(du -h "$OUTPUT_PATH" | cut -f1)
    echo "Size: $ISO_SIZE"
else
    print_error "Failed to create ISO"
    exit 1
fi

# USB Writing section
write_to_usb() {
    local device="$1"

    # Remove /dev/ prefix if user included it
    device=$(echo "$device" | sed 's|^/dev/||')
    local device_path="/dev/$device"

    if [ ! -b "$device_path" ]; then
        print_error "Device $device_path not found!"
        return 1
    fi

    # If AUTO_USB_WRITE is true, skip confirmation prompts
    if [ "$AUTO_USB_WRITE" = true ] && [ -n "$USB_DEVICE" ]; then
        print_warning "Writing to $device_path (automatic mode)"
        print_info "Device info:"
        lsblk "$device_path"
        print_info ""
        print_info "Writing ISO to $device_path..."
        if [ "$QUIET" = true ]; then
            sudo dd if="$OUTPUT_PATH" of="$device_path" bs=4M oflag=sync > /dev/null 2>&1
        else
            print_info "This will take several minutes..."
            sudo dd if="$OUTPUT_PATH" of="$device_path" bs=4M status=progress oflag=sync
        fi
        sync
        print_success "USB drive created successfully!"
        return 0
    fi

    # Interactive confirmation
    print_info ""
    print_warning "About to write to $device_path"
    print_info "Device info:"
    lsblk "$device_path"
    print_info ""
    read -p "Are you absolutely sure? Type 'yes' to continue: " CONFIRM

    if [ "$CONFIRM" = "yes" ]; then
        print_info ""
        print_info "Writing ISO to $device_path..."
        print_info "This will take several minutes..."
        if [ "$QUIET" = true ]; then
            sudo dd if="$OUTPUT_PATH" of="$device_path" bs=4M oflag=sync > /dev/null 2>&1
        else
            sudo dd if="$OUTPUT_PATH" of="$device_path" bs=4M status=progress oflag=sync
        fi
        sync
        print_success "USB drive created successfully!"
        print_info ""
        print_success "You can now boot from this USB to install Ubuntu with TPM2 encryption"
        return 0
    else
        print_warning "USB writing cancelled"
        return 1
    fi
}

# Handle USB writing based on flags
if [ "$SKIP_USB_PROMPT" = false ]; then
    # Default behavior: prompt user
    print_info ""
    print_header "USB Writing"

    print_info "The ISO has been created. You can now:"
    print_info "  1. Write it to a USB drive"
    print_info "  2. Use it in a VM for testing"
    print_info ""

    read -p "Would you like to write this ISO to a USB drive now? (y/N): " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info ""
        print_info "Available drives:"
        lsblk -d -o NAME,SIZE,TYPE,MODEL | grep disk
        print_info ""
        print_warning "WARNING: This will ERASE all data on the target drive!"
        print_info ""
        read -p "Enter the device name (e.g., sdb): " DEVICE

        if [ -z "$DEVICE" ]; then
            print_error "No device specified. Skipping USB writing."
        else
            write_to_usb "$DEVICE"
        fi
    else
        print_info ""
        print_info "To write the ISO to USB later, use:"
        echo "  sudo dd if=$OUTPUT_PATH of=/dev/sdX bs=4M status=progress && sync"
        print_info ""
        print_warning "Replace /dev/sdX with your actual USB device"
    fi
elif [ "$AUTO_USB_WRITE" = true ] && [ -n "$USB_DEVICE" ]; then
    # Automatic USB writing mode
    print_info ""
    print_header "USB Writing"
    write_to_usb "$USB_DEVICE"
fi

# Summary
print_info ""
print_header "Summary"

echo "✓ Custom autoinstall ISO created"
echo "✓ TPM2 encryption configured"
if [ "$QUIET" = false ]; then
    echo "✓ Temporary LUKS password: $TEMP_PASSWORD"
fi
print_info ""
print_info "Important notes:"
print_info "  - The temporary password will be automatically removed after TPM enrollment"
print_info "  - A recovery password will be generated and saved to /root/recovery-password.txt"
print_info "  - You MUST back up the recovery password after installation!"
print_info "  - Secure Boot must be enabled in BIOS before installation"
print_info "  - TPM 2.0 must be enabled in BIOS"
print_info ""
print_info "Next steps:"
print_info "  1. Verify BIOS settings (Secure Boot: ON, TPM 2.0: ON)"
print_info "  2. Boot from the USB drive"
print_info "  3. The installation will proceed automatically"
print_info "  4. After first boot, retrieve recovery password from /root/recovery-password.txt"
print_info "  5. Store recovery password in a secure location"
print_info ""
print_header "Done!"
