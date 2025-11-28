# Ubuntu 24.04 TPM2 Autoinstaller - Technical Documentation

This document provides comprehensive technical details about the TPM2-based autoinstaller implementation. It is intended for developers, system administrators, and AI agents who need to understand, maintain, or extend this system.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Security Model](#security-model)
3. [Storage Configuration](#storage-configuration)
4. [TPM2 Enrollment Process](#tpm2-enrollment-process)
5. [PCR Bank Selection](#pcr-bank-selection)
6. [Boot Process Flow](#boot-process-flow)
7. [Edge Cases and Error Handling](#edge-cases-and-error-handling)
8. [Testing Strategy](#testing-strategy)
9. [Future Enhancements](#future-enhancements)
10. [References](#references)

## Architecture Overview

### System Components

```
┌─────────────────────────────────────────────────────────────┐
│                     USB Installer                           │
│  ┌────────────┐  ┌──────────────┐  ┌──────────────────┐     │
│  │ Ubuntu ISO │  │ user-data    │  │ meta-data        │     │
│  │ (modified) │  │ (autoinstall)│  │ (cloud-init)     │     │
│  └────────────┘  └──────────────┘  └──────────────────┘     │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                   Installation Process                      │
│  ┌──────────┐  ┌──────────┐  ┌─────────────┐  ┌─────────┐   │
│  │ Partition│→ │ Install  │→ │ late-       │→ │ TPM2    │   │
│  │ Disk     │  │ Packages │  │ commands    │  │ Enroll  │   │
│  └──────────┘  └──────────┘  └─────────────┘  └─────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    Installed System                         │
│                                                             │
│  ┌───────────┐                                              │
│  │   UEFI    │  Loads shim (signed)                         │
│  └─────┬─────┘                                              │
│        │                                                    │
│        ▼                                                    │
│  ┌───────────┐                                              │
│  │   GRUB    │  Loads kernel + initramfs (signed)           │
│  └─────┬─────┘                                              │
│        │                                                    │
│        ▼                                                    │
│  ┌───────────────────────────────────────────┐              │
│  │ initramfs (systemd-cryptsetup)            │              │
│  │  - Measures volume key to PCR 15          │              │
│  │  - Unseals TPM2 token                     │              │
│  │  - Unlocks LUKS volume                    │              │
│  └──────────────────┬────────────────────────┘              │
│                     │                                       │
│                     ▼                                       │
│  ┌───────────────────────────────────────────┐              │
│  │ LVM on LUKS                               │              │
│  │  ├── vg0/root (/)                         │              │
│  │  └── vg0/swap                             │              │
│  └───────────────────────────────────────────┘              │
└─────────────────────────────────────────────────────────────┘
```

### Key Design Decisions

1. **LVM on LUKS (not LUKS on LVM)**
   - Encrypts all logical volumes with single key
   - Simplifies TPM2 enrollment (only one LUKS container)
   - Standard practice for full disk encryption

2. **Separate /boot partition**
   - Allows unencrypted boot files for emergency access
   - Required for GRUB to load kernel before decryption
   - 1GB size sufficient for multiple kernel versions

3. **systemd-cryptsetup over clevis**
   - Native systemd integration
   - Better PCR 15 measurement support
   - More straightforward configuration
   - Part of standard Ubuntu installation

4. **Embedded scripts in late-commands**
   - Eliminates need for separate script files on USB
   - Ensures scripts match configuration
   - Simplifies maintenance (single user-data file)

5. **Recovery password generation**
   - Critical safety mechanism
   - Generated automatically (no user intervention needed)
   - Stored in `/root` for post-installation backup

## Security Model

### Threat Model

**Protected Against:**
- Disk theft / lost device
- Unauthorized boot modifications
- Partition replacement attacks (via PCR 15)
- Firmware tampering (via PCR 0,2,7)
- Bootloader tampering (via Secure Boot + PCR 7,9)

**NOT Protected Against:**
- Evil maid attacks with sophisticated hardware
- Compromised firmware with valid signatures
- Physical access with time and TPM expertise
- Cold boot attacks (theoretical)
- BIOS password removal (some systems)

### Security Layers

**Layer 1: LUKS2 Encryption**
- AES-256-XTS encryption
- Strong password-based key derivation
- Multiple key slots (TPM token + recovery password)

**Layer 2: TPM 2.0 Sealing**
- Key sealed to TPM, unsealing requires:
  - Correct PCR values (0,2,7,9)
  - TPM physical presence (built into chip)
  - Secure Boot chain validation

**Layer 3: PCR 15 Measurement**
- Volume key derivative measured into PCR 15
- Prevents partition replacement attacks
- Measured by systemd-cryptsetup before unlock

**Layer 4: Secure Boot**
- Validates entire boot chain
- Prevents unsigned code execution
- Required for PCR 7 and 9 measurements

### Attack Surface Analysis

**Physical Access Attacks:**
1. **Disk cloning**: Protected (data remains encrypted)
2. **Partition replacement**: Protected (PCR 15 measurement fails)
3. **Evil maid (basic)**: Protected (Secure Boot detects modifications)
4. **Evil maid (advanced)**: NOT protected (no PIN to prevent extraction)
5. **TPM reset**: NOT protected (requires recovery password)

**Remote/Logical Attacks:**
1. **Software compromise**: Mitigated (Secure Boot limits unsigned code)
2. **Privilege escalation**: Standard Linux security applies
3. **Cold boot**: Mitigated (key not in RAM after unlock)

## Storage Configuration

### Partition Layout

```
/dev/sda (entire disk)
├── /dev/sda1 - EFI System Partition (512MB, FAT32)
│   └── /boot/efi
│
├── /dev/sda2 - Boot Partition (1GB, ext4, unencrypted)
│   └── /boot
│
└── /dev/sda3 - LUKS2 Encrypted Container (remaining space)
    └── /dev/mapper/cryptroot (dm-crypt)
        └── vg0 (LVM Volume Group)
            ├── vg0/swap (8GB, swap)
            │   └── (swap space)
            │
            └── vg0/root (remaining, ext4)
                └── / (root filesystem)
```

### Storage Configuration Rationale

**EFI Partition (512MB):**
- Standard size for EFI System Partition
- Stores UEFI bootloaders (shim, GRUB, fallback)
- FAT32 required by UEFI specification
- Unencrypted (required for UEFI to load bootloader)

**Boot Partition (1GB):**
- Stores kernel and initramfs
- Unencrypted for emergency access
- Allows rescue boot if TPM fails
- Size accommodates 5-10 kernel versions

**LUKS Container:**
- LUKS2 format (modern, supports TPM tokens)
- Contains entire LVM volume group
- Single unlock point simplifies management

**LVM Layer:**
- Flexible volume management
- Easy resizing of partitions
- Snapshot capability (for backups)
- Can add more volumes post-installation

**Swap (8GB):**
- Sized for typical systems (adjust as needed)
- Encrypted (protects sensitive data in swap)
- Inside LVM for flexibility

**Root (remaining space):**
- ext4 filesystem (stable, well-supported)
- Includes /home by default (simplicity)
- Can be resized within LVM

### Why LVM on LUKS (not LUKS on LVM)?

**LVM on LUKS:**
```
Physical → LUKS → LVM → Filesystems
```
- ✓ Single unlock (one TPM enrollment)
- ✓ All volumes encrypted
- ✓ Simpler configuration
- ✗ Can't have some volumes unencrypted

**LUKS on LVM:**
```
Physical → LVM → LUKS on each LV → Filesystems
```
- ✗ Multiple TPM enrollments needed
- ✓ Selective encryption possible
- ✗ Complex configuration
- ✗ More maintenance overhead

For full disk encryption, LVM on LUKS is the standard approach.

## TPM2 Enrollment Process

### Enrollment Flow

```
1. Installation Phase
   ├── Create LUKS volume with temporary password
   ├── Install base system
   └── Install TPM2 tools

2. late-commands Phase
   ├── Verify TPM availability
   ├── Enroll TPM2 with systemd-cryptenroll
   │   ├── Seal key to PCRs 0,2,7,9
   │   └── Store token in LUKS header
   ├── Update crypttab
   │   ├── Add tpm2-device=auto
   │   └── Add tpm2-measure-pcr=yes
   ├── Generate recovery password
   │   ├── Add to LUKS as second keyslot
   │   └── Save to /root/recovery-password.txt
   ├── Remove temporary password
   └── Update initramfs

3. First Boot
   ├── systemd-cryptsetup runs in initramfs
   ├── Measures volume key to PCR 15
   ├── Checks PCR values (0,2,7,9)
   ├── Unseals TPM token
   ├── Unlocks LUKS volume
   └── Continue boot normally
```

### systemd-cryptenroll Command

```bash
systemd-cryptenroll \
  --tpm2-device=auto \           # Auto-detect TPM device
  --tpm2-pcrs=0+2+7+9 \          # Seal to these PCR banks
  /dev/sda3                       # LUKS device
```

**What this does:**
1. Generates random key
2. Seals key to TPM with specified PCR values
3. Encrypts LUKS master key with this random key
4. Stores encrypted master key in LUKS header as "token"
5. Stores TPM-sealed random key in LUKS token metadata

### crypttab Configuration

```
cryptroot UUID=<uuid> none luks,discard,tpm2-device=auto,tpm2-measure-pcr=yes
```

**Options explained:**
- `cryptroot`: dm-crypt device name
- `UUID=<uuid>`: LUKS volume identifier
- `none`: No keyfile (TPM provides key)
- `luks`: LUKS encryption type
- `discard`: Enable TRIM for SSDs
- `tpm2-device=auto`: Auto-detect TPM
- `tpm2-measure-pcr=yes`: **Enable PCR 15 measurement**

### PCR 15 Measurement Process

This is the critical security feature that protects against partition replacement:

```
1. systemd-cryptsetup starts (in initramfs)
2. Reads crypttab, sees tpm2-measure-pcr=yes
3. Calculates volume key derivative
4. Extends PCR 15 with this value
5. Then attempts to unseal from TPM
6. TPM checks PCR values match sealed policy
7. If match, unseal key
8. Use key to unlock LUKS volume
```

**Why this matters:**
- PCR 15 value depends on actual LUKS volume key
- Different volume = different PCR 15 value
- Attacker can't replace partition with fake LUKS volume
- Even if they get PCR 0,2,7,9 values right, PCR 15 will differ

## PCR Bank Selection

### TPM Platform Configuration Registers (PCRs)

PCRs are 24-64 hash registers in the TPM that store measurements of the boot process.

**Our Selection: PCRs 0, 2, 7, 9, 15**

| PCR | Component | Why Include | Update Frequency |
|-----|-----------|-------------|------------------|
| 0 | UEFI firmware code | Detect firmware tampering | Rare (BIOS updates) |
| 2 | UEFI driver code | Detect option ROM modifications | Rare |
| 7 | Secure Boot state | Verify Secure Boot enabled | Never (unless manually changed) |
| 9 | Kernel, initramfs | Verify boot chain via shim | Moderate (kernel updates) |
| 15 | Volume key | Verify LUKS identity | Never (volume-specific) |

### Why NOT include certain PCRs:

**PCR 1 (Platform Config):**
- Changes with any BIOS setting
- Too fragile (breaks on minor config changes)
- Limited security benefit

**PCR 3, 4, 5 (Firmware config/tables):**
- Can change with hardware additions
- May change on firmware updates
- More maintenance burden than security value

**PCR 8 (Kernel command line):**
- Can change with boot options
- Would prevent recovery boot modes
- Already covered by PCR 9 in many configs

### PCR Update Scenarios

**Firmware Update:**
- PCRs 0, 2 change
- System prompts for password
- Auto-updates TPM enrollment (may require systemd 250+)
- Or: manual re-enrollment needed

**Kernel Update:**
- PCR 9 changes
- systemd should auto-update TPM
- If fails: use recovery password, re-enroll manually

**Secure Boot Config Change:**
- PCR 7 changes
- Must re-enroll TPM manually
- Prevents attackers from disabling Secure Boot

**Hardware Changes (e.g., new GPU):**
- Typically doesn't affect PCRs 0,2,7,9
- But may affect PCR 2 if option ROM loaded
- Test in non-production first

## Boot Process Flow

### Normal Boot Sequence

```
1. Power On
   └→ TPM PCRs reset to initial state

2. UEFI Firmware
   ├→ Measures itself into PCR 0
   ├→ Measures drivers into PCR 2
   ├→ Measures Secure Boot state into PCR 7
   └→ Loads shim bootloader (signed)

3. Shim Bootloader
   ├→ Validates GRUB signature (Secure Boot)
   ├→ Measures GRUB into PCR 4 (on some systems)
   └→ Loads GRUB

4. GRUB Bootloader
   ├→ Measures kernel+initramfs into PCR 9 (via shim)
   ├→ Loads kernel
   └→ Loads initramfs

5. Initramfs (early userspace)
   ├→ systemd starts
   ├→ systemd-cryptsetup@cryptroot.service runs
   │   ├→ Reads /etc/crypttab
   │   ├→ Sees tpm2-device=auto, tpm2-measure-pcr=yes
   │   ├→ Calculates volume key derivative
   │   ├→ Extends PCR 15 with derivative
   │   ├→ Attempts TPM unseal with PCR policy 0,2,7,9
   │   ├→ TPM checks current PCR values == sealed policy
   │   ├→ If match: TPM releases key
   │   └→ Unlocks /dev/sda3 → /dev/mapper/cryptroot
   ├→ LVM scans /dev/mapper/cryptroot
   │   └→ Discovers vg0/root, vg0/swap
   ├→ Mounts vg0/root to /sysroot
   └→ Pivot to main system

6. Main System
   └→ Boot continues normally
```

### Boot Failure Scenarios

**Scenario 1: PCR values don't match**
```
Cause: Firmware/kernel/config changed
Effect: TPM refuses to unseal key
Fallback: systemd-cryptsetup prompts for password
User Action: Enter recovery password
Post-Boot: Re-enroll TPM with new PCR values
```

**Scenario 2: TPM unavailable/failed**
```
Cause: TPM hardware issue, disabled in BIOS
Effect: Cannot unseal key
Fallback: Prompt for password
User Action: Enter recovery password
Post-Boot: Check TPM status, re-enable if disabled
```

**Scenario 3: PCR 15 measurement fails**
```
Cause: Wrong partition, corrupted LUKS header
Effect: PCR 15 value doesn't match sealed policy
Fallback: Prompt for password
User Action: Data may be lost, restore from backup
```

**Scenario 4: No password available**
```
Cause: Lost recovery password + TPM won't unseal
Effect: Cannot unlock encrypted partition
Fallback: None - data is permanently inaccessible
User Action: Reinstall (data loss)
```

## Edge Cases and Error Handling

### Installation-Time Edge Cases

**1. TPM not available during installation**
- Script detects and warns
- Installation continues without TPM enrollment
- System requires password on every boot
- Can enroll TPM manually post-installation

**2. Multiple LUKS devices detected**
- Script uses `head -n1` to select first device
- May enroll wrong device if multiple LUKS volumes present
- Mitigation: Validate single LUKS device before installation

**3. TPM enrollment fails**
- Script logs error to /var/log/tpm2-setup.log
- Temporary password NOT removed (safety mechanism)
- System boots with password requirement
- Administrator can investigate and retry enrollment

**4. initramfs update fails**
- Critical failure - system may not boot
- Script exits with error, installation marked failed
- Prevention: Ensure network connectivity for package downloads

**5. Recovery password add fails**
- Critical failure - could result in lockout
- Script exits before removing temporary password
- Ensures at least one password keyslot remains

### Runtime Edge Cases

**1. Firmware update changes PCR 0,2**
- Modern systemd (250+) may auto-update enrollment
- Older systems: prompt for password, require manual re-enrollment
- Mitigation: Document re-enrollment procedure

**2. Kernel update changes PCR 9**
- systemd-cryptenroll hook should auto-update
- May require systemd-cryptsetup 250+ with auto-enrollment
- Check `/usr/lib/systemd/system-generators/systemd-cryptsetup-generator`

**3. Secure Boot disabled (intentionally or maliciously)**
- PCR 7 changes value
- TPM unlock fails
- System prompts for password
- Admin must decide: re-enroll vs restore Secure Boot

**4. Disk cloning / UUID collision**
- If disk cloned, UUID remains same
- Clone will have different volume key → different PCR 15
- Clone won't unlock with TPM (security feature)
- Use recovery password, different for each disk

**5. TPM ownership taken by other software**
- Some enterprise management tools use TPM
- May interfere with our sealing
- Test in target environment first

### Error Handling Strategy

**During Installation (late-commands):**
```bash
set -euo pipefail  # Exit on error, undefined variables, pipe failures
```
- All commands checked for errors
- Errors logged to /var/log/tpm2-setup.log
- Critical failures prevent installation completion

**At Boot Time:**
- systemd-cryptsetup handles failures gracefully
- Falls back to password prompt on any error
- Logs to journal for troubleshooting

**Recovery Path:**
- Always maintain recovery password keyslot
- Never remove temporary password until recovery password added
- Document recovery procedures in README

## Testing Strategy

### Level 1: Configuration Validation (WSL/Local)

**test-config.sh script:**
```bash
./test-config.sh
```

Tests:
- YAML syntax validation
- Required sections present
- Placeholder values identified
- Storage configuration structure
- TPM enrollment script presence

Can be run in WSL without full Linux environment.

### Level 2: ISO Building (Linux)

**create-usb.sh script:**
```bash
./create-usb.sh
```

Tests:
- ISO download
- ISO extraction
- Configuration injection
- Password replacement
- GRUB modification
- ISO rebuild

Verifies USB creation process without installation.

### Level 3: VM Installation (QEMU/VirtualBox)

**QEMU with TPM emulation:**
```bash
# Install swtpm
apt install swtpm swtpm-tools

# Start TPM emulator
mkdir /tmp/mytpm
swtpm socket --tpmstate dir=/tmp/mytpm \
  --ctrl type=unixio,path=/tmp/mytpm/swtpm-sock \
  --tpm2 \
  --log level=20

# Run QEMU with TPM
qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 \
  -cdrom ubuntu-24.04-autoinstall-tpm2.iso \
  -hda test-disk.img \
  -chardev socket,id=chrtpm,path=/tmp/mytpm/swtpm-sock \
  -tpmdev emulator,id=tpm0,chardev=chrtpm \
  -device tpm-tis,tpmdev=tpm0 \
  -bios /usr/share/ovmf/OVMF.fd
```

Tests:
- Complete installation process
- TPM enrollment
- First boot auto-unlock
- Recovery password access
- Re-enrollment after PCR changes

### Level 4: Physical Hardware

**Pre-deployment checklist:**
1. Verify TPM 2.0 present and enabled
2. Verify Secure Boot can be enabled
3. Test installation on identical hardware first
4. Boot and verify TPM auto-unlock
5. Test recovery password
6. Test firmware update scenario
7. Document any hardware-specific issues

**Production deployment:**
1. Image one machine fully
2. Test for 24-48 hours
3. Verify remote access, updates, recovery
4. Roll out to additional machines
5. Maintain recovery password database

### Validation Points

**Post-Installation:**
```bash
# Check TPM enrollment
cryptsetup luksDump /dev/sda3 | grep -A 10 "systemd-tpm2"

# Verify crypttab
cat /etc/crypttab | grep "tpm2-measure-pcr=yes"

# Check initramfs contains TPM support
lsinitramfs /boot/initrd.img-$(uname -r) | grep tpm

# Verify recovery password keyslot
cryptsetup luksDump /dev/sda3 | grep "Key Slot"
```

**Post-Reboot:**
```bash
# Check unlock was automatic (no password in journal)
journalctl -b | grep cryptsetup

# Verify TPM unsealing worked
journalctl -b | grep "tpm2"

# Check PCR values
tpm2_pcrread

# Test recovery password
# (in recovery scenario, not production)
```

## Future Enhancements

### Near-term (Next Release)

1. **Interactive Configuration**
   - Prompt for username/hostname during USB creation
   - SSH key selection dialog
   - Partition size customization

2. **Pre-flight Checks**
   - Validate target hardware has TPM before installation
   - Check Secure Boot status before proceeding
   - Warn if BIOS settings incorrect

3. **Post-Installation Validation**
   - Automatic verification script runs on first boot
   - Sends email/notification with recovery password
   - Validates TPM enrollment succeeded

4. **Improved Error Reporting**
   - Send installation logs to remote server
   - Generate detailed error reports
   - Better diagnostic information

### Mid-term (Future Versions)

1. **PIN Option**
   - Make PIN requirement configurable at USB creation
   - Add post-installation script to add/remove PIN
   - Document security trade-offs clearly

2. **Multi-Disk Support**
   - Handle systems with multiple disks
   - Support RAID configurations
   - Encrypt multiple disks with same TPM

3. **Network-Based Installation**
   - PXE boot support
   - Download autoinstall config from server
   - Centralized password/configuration management

4. **Recovery USB**
   - Separate USB for recovery operations
   - Automated re-enrollment scripts
   - Backup/restore functionality

### Long-term (Research)

1. **Remote Attestation**
   - Report PCR values to management server
   - Detect unauthorized configuration changes
   - Centralized compliance monitoring

2. **Clevis Integration**
   - Support both systemd-cryptenroll and clevis
   - Tang server for network-bound encryption
   - Shamir's Secret Sharing for redundancy

3. **LUKS2 Online Reencryption**
   - Change encryption keys without downtime
   - Key rotation policies
   - Cryptographic agility

4. **Measured Boot Integration**
   - IMA (Integrity Measurement Architecture)
   - Verification of all executables before load
   - Runtime integrity monitoring

## References

### Official Documentation

**Ubuntu Autoinstall:**
- Quickstart: https://canonical-subiquity.readthedocs-hosted.com/en/latest/howto/autoinstall-quickstart.html
- Reference: https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html

**Curtin Storage:**
- Storage Configuration: https://curtin.readthedocs.io/en/stable/topics/storage.html

**systemd-cryptenroll:**
- Man page: `man systemd-cryptenroll`
- Docs: https://www.freedesktop.org/software/systemd/man/systemd-cryptenroll.html

**systemd-cryptsetup:**
- Man page: `man systemd-cryptsetup@.service`
- crypttab: `man crypttab`

**TPM 2.0:**
- TPM2 Tools: https://github.com/tpm2-software/tpm2-tools
- TCG Specs: https://trustedcomputinggroup.org/resource/tpm-library-specification/

### Security Analysis

**TPM2 Bypass Attack:**
- Original article: https://oddlama.org/blog/bypassing-disk-encryption-with-tpm2-unlock/
- Explains why PCR 15 measurements are critical
- Source of our security model design

**LUKS:**
- Specification: https://gitlab.com/cryptsetup/cryptsetup/-/wikis/LUKS-standard
- Best practices: https://gitlab.com/cryptsetup/cryptsetup/-/wikis/FrequentlyAskedQuestions

### Related Projects

**Arch Linux TPM2:**
- https://wiki.archlinux.org/title/Trusted_Platform_Module#systemd-cryptenroll

**Clevis:**
- https://github.com/latchset/clevis
- Alternative TPM binding solution

## Appendix: Command Reference

### TPM Operations

```bash
# Check TPM status
tpm2_getcap properties-fixed

# Read PCR values
tpm2_pcrread

# List TPM objects
tpm2_getcap handles-persistent

# Clear TPM (WARNING: Destroys keys)
tpm2_clear
```

### LUKS Operations

```bash
# Dump LUKS header
cryptsetup luksDump /dev/sda3

# List keyslots
cryptsetup luksDump /dev/sda3 | grep "Key Slot"

# Add key
cryptsetup luksAddKey /dev/sda3

# Remove key (by keyslot)
cryptsetup luksKillSlot /dev/sda3 0

# Test passphrase
cryptsetup luksOpen --test-passphrase /dev/sda3
```

### systemd-cryptenroll Operations

```bash
# Enroll TPM
systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+2+7+9 /dev/sda3

# Enroll with PIN
systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+2+7+9 --tpm2-with-pin=true /dev/sda3

# List enrollments
systemd-cryptenroll /dev/sda3

# Remove TPM enrollment
systemd-cryptenroll --wipe-slot=tpm2 /dev/sda3

# Remove specific keyslot
systemd-cryptenroll --wipe-slot=0 /dev/sda3
```

### Debugging

```bash
# Check systemd-cryptsetup status
systemctl status systemd-cryptsetup@cryptroot.service

# View cryptsetup logs
journalctl -u systemd-cryptsetup@*

# Enable debug logging
systemctl edit systemd-cryptsetup@cryptroot.service
# Add:
# [Service]
# Environment=SYSTEMD_LOG_LEVEL=debug

# Check initramfs contents
lsinitramfs /boot/initrd.img-$(uname -r) | less

# Rebuild initramfs
update-initramfs -u -k all

# Verify crypttab syntax
systemd-cryptenroll --verify /etc/crypttab
```

---

**Document Version:** 1.0
**Last Updated:** November 2024
**Target Ubuntu Version:** 24.04 LTS
**Systemd Version:** 255+
