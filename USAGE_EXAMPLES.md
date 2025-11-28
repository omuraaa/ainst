# create-usb.sh Usage Examples

This document provides practical examples of using the improved `create-usb.sh` script with various options and flags.

## Basic Usage

### 1. Interactive Mode (Default)
```bash
./create-usb.sh
```
- Downloads Ubuntu ISO if not present
- Generates random temporary password
- Prompts whether to write to USB
- Shows all progress information

### 2. Quick Help
```bash
./create-usb.sh --help
```
Shows complete usage information and all available options.

## Common Scenarios

### Using an Existing ISO

If you already have the Ubuntu ISO downloaded:
```bash
./create-usb.sh -i /path/to/ubuntu-24.04-live-server-amd64.iso
```

### Create ISO Only (No USB Writing)
```bash
./create-usb.sh -s
```
Or with custom output path:
```bash
./create-usb.sh -s -o /tmp/my-custom-installer.iso
```

### Automatic USB Writing
```bash
# Write to /dev/sdb automatically
./create-usb.sh -u sdb

# Or specify full path
./create-usb.sh -u /dev/sdb
```

### Quiet Mode for Scripting
```bash
./create-usb.sh -q -u sdb -s
```
Suppresses non-essential output for use in automated scripts.

## Advanced Usage

### Custom Configuration Directory
```bash
./create-usb.sh -c ./my-configs
```
Looks for `user-data` and `meta-data` in `./my-configs/` directory.

### Custom Temporary Password
```bash
./create-usb.sh -p "MySecurePassword123!"
```
Uses your specified password instead of generating one.

### Clean Up After Build
```bash
./create-usb.sh --cleanup
```
Removes the `build/` directory after successful ISO creation.

### Custom Ubuntu Version
```bash
./create-usb.sh --version 23.10
```
Downloads and uses Ubuntu 23.10 instead of 24.04.

### Custom ISO URL
```bash
./create-usb.sh --iso-url https://mirror.example.com/ubuntu-24.04-live-server-amd64.iso
```

## Combined Options

### Production Workflow
```bash
# Use existing ISO, custom config, automatic USB write, quiet mode
./create-usb.sh \
  -i ~/Downloads/ubuntu-24.04-live-server-amd64.iso \
  -c ./production-configs \
  -u sdb \
  -q \
  --cleanup
```

### Testing Workflow
```bash
# Create ISO only for VM testing, keep build artifacts
./create-usb.sh \
  -s \
  -o test-installer.iso \
  -c ./test-configs
```

### CI/CD Pipeline
```bash
# Fully automated, minimal output
./create-usb.sh \
  -i ubuntu-24.04-live-server-amd64.iso \
  -o /output/autoinstall.iso \
  -s \
  -q \
  --cleanup
```

## Option Reference Table

| Short | Long | Argument | Description |
|-------|------|----------|-------------|
| `-h` | `--help` | None | Show help and exit |
| `-i` | `--iso-path` | PATH | Use existing ISO file |
| `-o` | `--output` | PATH | Output ISO path |
| `-u` | `--usb` | DEVICE | Write to USB automatically |
| `-w` | `--write-usb` | None | Prompt for USB writing |
| `-s` | `--skip-usb` | None | Skip USB writing prompt |
| `-p` | `--password` | PASS | Use custom password |
| `-c` | `--config-dir` | DIR | Custom config directory |
| `-q` | `--quiet` | None | Suppress non-essential output |
| N/A | `--cleanup` | None | Remove build directory after |
| N/A | `--iso-url` | URL | Custom ISO download URL |
| N/A | `--version` | VERSION | Ubuntu version to use |

## Environment-Specific Examples

### WSL (Windows Subsystem for Linux)
```bash
# ISO stored in Windows filesystem, output to Linux
./create-usb.sh \
  -i /mnt/c/Users/YourName/Downloads/ubuntu-24.04-live-server-amd64.iso \
  -o ~/autoinstall.iso \
  -s
```

### Network Share
```bash
# ISO from network share, write to USB
./create-usb.sh \
  -i /mnt/network/isos/ubuntu-24.04-live-server-amd64.iso \
  -u sdb
```

### Multiple Configurations
```bash
# Production config
./create-usb.sh -c ./configs/production -o prod-installer.iso -s

# Development config
./create-usb.sh -c ./configs/development -o dev-installer.iso -s

# Test config
./create-usb.sh -c ./configs/test -o test-installer.iso -s
```

## Error Handling

### Missing Dependencies
If dependencies are missing, the script will tell you:
```bash
./create-usb.sh
# Output:
# ✗ xorriso not found. Install with: apt install xorriso
# ✗ Missing required dependencies. Please install them and try again.
```

### Invalid ISO Path
```bash
./create-usb.sh -i /wrong/path.iso
# Output:
# ✗ ISO file not found: /wrong/path.iso
```

### Invalid USB Device
```bash
./create-usb.sh -u sdz
# Output:
# ✗ Device /dev/sdz not found!
```

### Missing Config Files
```bash
./create-usb.sh -c /wrong/dir
# Output:
# ✗ user-data file not found: /wrong/dir/user-data
```

## Tips and Best Practices

### 1. Verify Before Writing
Always run without `-u` first to verify the ISO builds correctly:
```bash
./create-usb.sh -s  # Just create ISO
# Test the ISO in a VM
# If it works, then write to USB:
./create-usb.sh -i ubuntu-24.04-autoinstall-tpm2.iso -u sdb
```

### 2. List Available Drives First
```bash
lsblk -d -o NAME,SIZE,TYPE,MODEL | grep disk
# Then use the correct device:
./create-usb.sh -u sdb
```

### 3. Keep the Build Directory
By default, the script keeps `build/` for debugging. Remove it manually or use `--cleanup`.

### 4. Save Passwords Securely
If using custom passwords, don't put them in shell history:
```bash
# Read from file
./create-usb.sh -p "$(cat password.txt)"

# Or use environment variable
export LUKS_PASS="MyPassword"
./create-usb.sh -p "$LUKS_PASS"
```

### 5. Version Pinning
For reproducible builds, always specify exact versions:
```bash
./create-usb.sh \
  --version 24.04 \
  --iso-url https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso
```

## Troubleshooting

### Permission Denied
Mounting ISOs and writing to USB requires sudo. The script will prompt when needed.

### ISO Download Fails
Use `-i` to provide a manually downloaded ISO:
```bash
wget https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso
./create-usb.sh -i ubuntu-24.04-live-server-amd64.iso
```

### USB Write is Slow
This is normal. Writing 2-3GB takes several minutes. Use `status=progress` to see progress (enabled by default).

### Build Directory Issues
Remove and try again:
```bash
rm -rf build/
./create-usb.sh
```

## Integration Examples

### Makefile Integration
```makefile
.PHONY: iso usb clean

iso:
	./create-usb.sh -s -o build/installer.iso

usb: iso
	./create-usb.sh -i build/installer.iso -u $(USB_DEVICE)

clean:
	rm -rf build/
	rm -f ubuntu-*.iso
```

### Shell Script Integration
```bash
#!/bin/bash
set -e

# Build multiple ISOs with different configs
for env in prod staging dev; do
  echo "Building $env installer..."
  ./create-usb.sh \
    -c "./configs/$env" \
    -o "installer-$env.iso" \
    -s \
    -q
done
```

### Ansible Playbook Integration
```yaml
- name: Create autoinstall USB
  command: >
    ./create-usb.sh
    -i {{ iso_path }}
    -u {{ usb_device }}
    -c {{ config_dir }}
    -q
  args:
    chdir: /path/to/autoinstaller
```

## See Also

- [README.md](README.md) - Project overview and setup
- [CLAUDE.md](CLAUDE.md) - Comprehensive technical documentation
- [user-data](user-data) - Autoinstall configuration file
