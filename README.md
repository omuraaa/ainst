# Ubuntu 24.04 TPM2 Autoinstaller

Automated USB installer for Ubuntu 24.04 LTS with TPM2-based full disk encryption. This installer provides a fully automated, secure setup with encrypted LVM partitions that automatically unlock using the system's TPM 2.0 chip.

## Features

- **Fully Automated Installation**: No manual partitioning or configuration required
- **TPM2-based Encryption**: Disk automatically unlocks on boot using TPM 2.0
- **No PIN Required**: Seamless boot experience while maintaining security
- **LVM on LUKS**: Flexible volume management with full disk encryption
- **PCR 15 Measurements**: Protection against partition replacement attacks
- **Secure Boot Integration**: Requires and enforces Secure Boot for trusted boot chain
- **Recovery Password**: Automatic generation of backup password for TPM failure scenarios

## Security Model

This autoinstaller implements a layered security approach:

### What it protects against:
- **Disk theft**: Encrypted data is inaccessible without the TPM
- **Partition replacement**: PCR 15 measurements verify LUKS volume identity
- **Unauthorized boot modifications**: Secure Boot and PCR measurements detect tampering
- **Firmware tampering**: PCR 0,2,7 measurements include firmware state

### What it does NOT protect against:
- **Sophisticated evil maid attacks**: Physical access with sufficient time and expertise
- **Compromised firmware**: If Secure Boot chain is compromised, encryption can be bypassed
- **TPM extraction attacks**: Advanced attacks requiring specialized equipment

### Trade-off:
This setup prioritizes **convenience** (no PIN required) over protection against physical access attacks. This is appropriate for:
- Corporate environments with physical security
- Personal devices in secure locations
- Scenarios where boot convenience is important

For maximum security, consider adding a PIN to the TPM unlock (see Advanced Configuration section).

## Prerequisites

### Hardware Requirements
- **TPM 2.0** chip (enabled in BIOS)
- **Secure Boot** capable system (must be enabled)
- **UEFI** firmware (not legacy BIOS)
- Minimum 8GB USB drive
- Target system with at least 20GB storage

### Software Requirements (for building USB)
- Linux system (Ubuntu, Debian, or WSL)
- `xorriso` package
- `curl` or `wget`
- `openssl`
- `sudo` access

Install on Ubuntu/Debian:
```bash
sudo apt update
sudo apt install xorriso curl openssl
```

## Pre-Installation Checklist

Before creating the installer USB, complete these steps:

### 1. Customize Configuration

Edit `user-data` to customize:

**SSH Public Key** (REQUIRED):
```yaml
ssh:
  authorized-keys:
    - "ssh-rsa AAAAB3... your-actual-public-key"
```

**Username and Hostname** (Optional):
```yaml
identity:
  hostname: ubuntu-secure  # Change to your preferred hostname
  username: admin           # Change to your preferred username
```

**User Password** (Optional):
Generate a password hash:
```bash
mkpasswd -m sha-512
```
Replace the password field in user-data with the generated hash.

### 2. Verify BIOS Settings

On your target system, ensure:
- **Secure Boot**: ENABLED
- **TPM 2.0**: ENABLED and not in restricted mode
- **Boot Mode**: UEFI (not Legacy/CSM)

Set a BIOS password to prevent users from disabling Secure Boot.

### 3. Validate Configuration

Run the validation script:
```bash
cd autoinstaller
./test-config.sh
```

Fix any warnings or errors before proceeding.

## Creating the Installer USB

### Option 1: Automated Script (Recommended)

```bash
cd autoinstaller
./create-usb.sh
```

The script will:
1. Download Ubuntu 24.04 ISO (if not present)
2. Generate a random temporary LUKS password
3. Extract and modify the ISO
4. Add autoinstall configuration
5. Rebuild the bootable ISO
6. Optionally write to USB drive

### Option 2: Manual ISO Creation

If you prefer to write the ISO to USB manually:

1. Create the ISO:
```bash
./create-usb.sh
# When prompted, choose 'N' to skip USB writing
```

2. Write to USB manually:
```bash
sudo dd if=ubuntu-24.04-autoinstall-tpm2.iso of=/dev/sdX bs=4M status=progress && sync
```
Replace `/dev/sdX` with your USB device (e.g., `/dev/sdb`).

**WARNING**: This will erase all data on the USB drive!

## Installation Process

### Step 1: Boot from USB

1. Insert the USB drive into the target system
2. Boot from USB (usually F12, F2, or DEL to access boot menu)
3. Select the USB drive from the boot menu

### Step 2: Automated Installation

The installation will proceed automatically:

1. **Partitioning**: Automatic creation of EFI, boot, and encrypted LVM partitions
2. **Base System**: Ubuntu 24.04 minimal server installation
3. **Package Installation**: TPM2 tools and cryptsetup
4. **TPM Enrollment**: Automatic binding of LUKS key to TPM 2.0
5. **Recovery Password**: Generation and storage of backup password

Installation takes approximately 15-30 minutes depending on hardware.

### Step 3: First Boot

1. Remove the USB drive
2. System will reboot automatically
3. **IMPORTANT**: On first boot, you may be prompted for the LUKS password once
   - This is normal and happens before initramfs is fully updated
   - Enter the temporary password if prompted (visible in create-usb.sh output)
4. After initramfs update, subsequent boots will use TPM2 auto-unlock

## Post-Installation

### Critical: Backup Recovery Password

Immediately after first successful boot:

1. Log in to the system
2. Become root: `sudo su -`
3. View the recovery password:
```bash
cat /root/recovery-password.txt
```

4. **Back this up to secure external storage!**
   - Print it and store in a safe
   - Store in a password manager
   - Keep encrypted backup on separate device

**Without this password, data is unrecoverable if TPM fails!**

### Verify TPM Enrollment

Check that TPM2 unlock is working:

```bash
sudo cryptsetup luksDump /dev/sda3
```

Look for a keyslot with "systemd-tpm2" in the metadata.

Check crypttab configuration:
```bash
cat /etc/crypttab
```

Should contain: `tpm2-device=auto,tpm2-measure-pcr=yes`

### Optional: Remove Recovery Password File

After backing up the password externally:
```bash
sudo shred -u /root/recovery-password.txt
```

This removes the plain-text password file from the system.

## Recovery Procedures

### Scenario 1: TPM Failure / Hardware Changes

If the system prompts for a password at boot:

1. Enter the recovery password from your backup
2. System will boot normally
3. After boot, re-enroll the TPM:
```bash
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+2+7+9 /dev/sda3
```

### Scenario 2: Firmware/Kernel Update Changes PCRs

If TPM unlock fails after update:

1. Enter recovery password at boot
2. System may auto-update TPM enrollment
3. If not, manually re-enroll (see above)

### Scenario 3: Unable to Boot

If the system won't boot:

1. Boot from Ubuntu live USB
2. Unlock the encrypted partition:
```bash
sudo cryptsetup open /dev/sda3 cryptroot
```
Enter recovery password when prompted.

3. Mount the filesystem:
```bash
sudo mount /dev/vg0/root /mnt
sudo mount /dev/sda2 /mnt/boot
sudo mount /dev/sda1 /mnt/boot/efi
```

4. Chroot and repair:
```bash
sudo mount --bind /dev /mnt/dev
sudo mount --bind /proc /mnt/proc
sudo mount --bind /sys /mnt/sys
sudo chroot /mnt
```

5. Fix issues and update initramfs:
```bash
update-initramfs -u -k all
```

## Troubleshooting

### Installation fails with "No TPM found"

- Check BIOS: Ensure TPM 2.0 is enabled
- Some systems call it "PTT" (Platform Trust Technology)
- System will continue but won't have TPM auto-unlock

### System prompts for password on every boot

- TPM enrollment may have failed
- Check logs: `sudo journalctl -u systemd-cryptsetup@*`
- Verify Secure Boot is enabled
- Check PCR values haven't changed: `tpm2_pcrread`

### Can't connect via SSH after installation

- Verify you added your SSH public key to user-data
- Check SSH service: `sudo systemctl status ssh`
- Verify firewall rules: `sudo ufw status`

### Installation hangs or fails

- Check network connectivity (needed for package downloads)
- Verify UEFI mode (not legacy BIOS)
- Check system logs in installer: Alt+F2 during installation

## Advanced Configuration

### Adding a TPM PIN for Extra Security

For maximum security, add a PIN requirement:

1. After installation, enroll with PIN:
```bash
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+2+7+9 --tpm2-with-pin=true /dev/sda3
```

2. Update crypttab:
```bash
sudo nano /etc/crypttab
# Add: tpm2-pin=true to the options
```

3. Update initramfs:
```bash
sudo update-initramfs -u -k all
```

### Customizing Partition Sizes

Edit the `storage` section in `user-data`:

- Swap size: Change `lv-swap` size value (default 8G)
- Add separate /home: Add additional LVM partition configuration

### Changing PCR Banks

For different security/convenience trade-offs, modify the `systemd-cryptenroll` command in user-data:

- **More secure**: Add PCR 1,4,5 (more components measured)
- **More flexible**: Remove PCR 9 (allows kernel updates without re-enrollment)

## Technical Details

See `CLAUDE.md` for comprehensive technical documentation including:
- Complete architecture explanation
- Storage layout details
- TPM2 enrollment process
- PCR bank selection rationale
- Security model analysis

See `SECURITY.md` for detailed security analysis including:
- Threat model
- Attack vectors and mitigations
- Comparison with PIN-based approach
- Operational security recommendations

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review `CLAUDE.md` for technical details
3. Check Ubuntu autoinstall documentation: https://canonical-subiquity.readthedocs-hosted.com/
4. Open an issue in the project repository

## License

This autoinstaller configuration is provided as-is for use with Ubuntu 24.04 LTS.
Ubuntu is licensed under various open source licenses by Canonical Ltd.

## Warnings

- This will ERASE ALL DATA on the target system
- TPM failure without recovery password = PERMANENT DATA LOSS
- Changing hardware may break TPM unlock
- Disabling Secure Boot will break TPM unlock
- Not suitable for systems requiring protection against sophisticated physical attacks
