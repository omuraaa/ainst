# Security Analysis - Ubuntu 24.04 TPM2 Autoinstaller

## Executive Summary

This document provides a comprehensive security analysis of the TPM2-based autoinstaller, including threat modeling, attack vector analysis, and operational security recommendations.

**Security Posture:** Medium-High

The system provides strong protection against common threats (disk theft, unauthorized access) while prioritizing usability (no PIN required). It is NOT designed to protect against sophisticated physical attacks by determined adversaries with specialized equipment and time.

**Recommended Use Cases:**
- Corporate workstations with physical security
- Personal devices in secure locations
- Development/testing environments
- Scenarios prioritizing boot convenience

**NOT Recommended For:**
- High-security government/military applications
- Devices in hostile environments
- Protection against nation-state actors
- Systems containing classified information

## Threat Model

### Assets

1. **Data at Rest**
   - User files, documents, credentials
   - System configuration
   - Application data
   - Encryption keys

2. **System Integrity**
   - Boot chain (firmware → bootloader → kernel)
   - System software
   - Configuration files

3. **Availability**
   - Ability to boot and access data
   - Recovery from failures

### Threat Actors

**Opportunistic Thief (Low Skill)**
- Steals laptop for hardware value
- No technical expertise
- No specialized tools
- **Protection Level: Full**

**Technical Thief (Medium Skill)**
- Steals laptop for data
- Basic IT knowledge
- Common tools (USB boot, disk cloning)
- **Protection Level: Full**

**Corporate Espionage (Medium-High Skill)**
- Targets specific data
- May have inside knowledge
- Access to commercial forensic tools
- Limited time with device
- **Protection Level: Good**

**Evil Maid (High Skill)**
- Physical access to device (hotel, office)
- Moderate time window (minutes to hours)
- Specialized hardware (bus pirating, TPM sniffing)
- **Protection Level: Partial**
  - Basic evil maid: Detected by Secure Boot
  - Advanced evil maid: May succeed

**Nation State (Very High Skill)**
- Unlimited resources
- Custom hardware/firmware
- Can compromise supply chain
- **Protection Level: Insufficient**
  - This system is NOT designed for this threat level

### Attack Vectors

1. **Physical Access**
   - Device theft
   - Evil maid attack
   - Hardware tampering
   - TPM extraction

2. **Logical Access**
   - Malware/rootkit
   - Privilege escalation
   - Supply chain compromise
   - Social engineering

3. **Side Channel**
   - Cold boot attack
   - Power analysis
   - Timing attacks
   - Electromagnetic analysis

## Attack Analysis

### Vector 1: Simple Disk Theft

**Attack:** Steal laptop, clone disk, attempt to access data

**Attacker Actions:**
1. Steal device
2. Connect disk to forensic workstation
3. Attempt to mount filesystem
4. Run data recovery tools

**System Response:**
- LUKS encryption prevents direct access
- Data appears as random noise
- No key available without TPM

**Result:** ✅ **ATTACK DEFEATED**

**Mitigation Effectiveness:** 100%

---

### Vector 2: Partition Replacement Attack

**Attack:** Replace encrypted partition with fake LUKS volume, extract key from TPM

**Attacker Actions:**
1. Boot device, observe boot process
2. Clone encrypted partition
3. Create new LUKS volume with known password
4. Replace partition, keep UUID same
5. Boot device, let TPM unlock
6. Capture key, apply to real partition

**System Response:**
- systemd-cryptsetup measures volume key to PCR 15
- PCR 15 value differs for fake partition
- TPM refuses to unseal (PCR policy violation)
- System prompts for password

**Result:** ✅ **ATTACK DEFEATED**

**Mitigation Effectiveness:** 100% (with PCR 15 measurement)

**Note:** Without PCR 15 measurement, this attack succeeds. This is why `tpm2-measure-pcr=yes` is critical.

---

### Vector 3: Basic Evil Maid Attack

**Attack:** Modify bootloader while device unattended, capture key on next boot

**Attacker Actions:**
1. Brief physical access (minutes)
2. Boot from USB
3. Modify GRUB to log keystrokes
4. Wait for user to boot
5. Retrieve logged password

**System Response:**
- Secure Boot validates all boot components
- Modified GRUB lacks valid signature
- Secure Boot refuses to load
- Device won't boot
- User notices boot failure

**Result:** ✅ **ATTACK DETECTED**

**Mitigation Effectiveness:** High (requires user awareness)

**Caveat:** User must notice boot failure and investigate

---

### Vector 4: Advanced Evil Maid Attack

**Attack:** Replace entire boot chain with validly-signed components, extract TPM key

**Attacker Actions:**
1. Physical access (30+ minutes)
2. Replace firmware with modified version (valid signatures)
3. Modified firmware intercepts TPM operations
4. Log unsealing process
5. Restore original firmware
6. Extract key from logs

**System Response:**
- PCR 0,2 change due to different firmware
- TPM refuses to unseal (PCR policy violation)
- System prompts for password
- BUT: Modified firmware could potentially capture password

**Result:** ⚠️ **PARTIAL PROTECTION**

**Mitigation Effectiveness:** Moderate

**Why it's hard:**
- Requires valid firmware signatures (difficult to obtain)
- PCR changes require user to enter password
- Time-consuming (30+ minutes uninterrupted access)

**Why it's possible:**
- No PIN to prevent TPM unsealing attempts
- Advanced attacker may have stolen firmware signing keys
- User might not notice subtle boot differences

**Countermeasure:** Add TPM PIN (see recommendations)

---

### Vector 5: TPM Extraction Attack

**Attack:** Physically extract TPM chip, extract sealed keys

**Attacker Actions:**
1. Disassemble laptop
2. Desolder TPM chip
3. Use specialized TPM analysis hardware
4. Attempt to extract sealed keys
5. Attempt to brute-force TPM authorization

**System Response:**
- TPM has physical tamper resistance
- Keys are hardware-bound
- TPM designed to resist extraction
- BUT: Not impossible with nation-state resources

**Result:** ⚠️ **DEPENDS ON ATTACKER RESOURCES**

**Mitigation Effectiveness:** Moderate to High

**Factors:**
- Consumer TPM: Moderate resistance
- Time: Days to weeks required
- Cost: $10k-$100k+ in equipment
- Success rate: Unknown, likely variable

**Countermeasure:** Consider PIN (makes brute-force harder)

---

### Vector 6: Cold Boot Attack

**Attack:** Freeze RAM, extract encryption key from memory

**Attacker Actions:**
1. Access to powered-on, unlocked system
2. Freeze RAM chips with liquid nitrogen
3. Quickly remove RAM
4. Read RAM contents in forensic setup
5. Search for encryption keys

**System Response:**
- Keys may be in RAM briefly after unlock
- BUT: systemd-cryptsetup doesn't keep keys in RAM long
- Key only in kernel memory during unlock
- Kernel may zero keys after use

**Result:** ✅ **LOW PROBABILITY**

**Mitigation Effectiveness:** Good

**Why unlikely:**
- Very short time window (seconds)
- Requires access to running, unlocked system
- LUKS keys zeroed after unlock
- Difficult to execute reliably

---

### Vector 7: BIOS/Firmware Modification

**Attack:** Modify BIOS to disable Secure Boot or TPM

**Attacker Actions:**
1. Boot into BIOS
2. Disable Secure Boot
3. Disable or clear TPM
4. Boot with custom kernel
5. Attempt to access data

**System Response:**
- BIOS password should prevent changes
- Disabling Secure Boot changes PCR 7
- Clearing TPM destroys sealed keys
- Can't boot encrypted system

**Result:** ✅ **ATTACK PREVENTED** (with BIOS password)

**Mitigation Effectiveness:** High (if BIOS password set)

**Critical:** MUST set BIOS password to prevent Secure Boot disable

---

### Vector 8: Supply Chain Attack

**Attack:** Compromise during manufacturing or shipping

**Attacker Actions:**
1. Intercept device before delivery
2. Install hardware implant
3. Install modified firmware
4. Deliver to target

**System Response:**
- Would be indistinguishable from legitimate device
- Firmware measurements would include backdoor
- TPM enrollment would seal to compromised state

**Result:** ❌ **NO PROTECTION**

**Mitigation Effectiveness:** None

**Countermeasure:** Purchase from trusted suppliers, inspect for tampering

---

### Vector 9: Malware/Rootkit After Boot

**Attack:** Compromise system after successful boot

**Attacker Actions:**
1. User boots system (TPM unlocks)
2. Exploit vulnerability to gain root
3. Install rootkit
4. Access unencrypted data

**System Response:**
- Standard Linux security mechanisms apply
- Encryption irrelevant (system already unlocked)
- Secure Boot may prevent some rootkits
- TPM doesn't help post-boot

**Result:** ⚠️ **ENCRYPTION DOESN'T PROTECT**

**Mitigation Effectiveness:** N/A (out of scope)

**Note:** Disk encryption protects data at rest, not data in use

**Countermeasures:**
- Keep system updated
- Use AppArmor/SELinux
- Monitor for suspicious activity
- Regular backups

---

### Vector 10: Recovery Password Theft

**Attack:** Steal recovery password, unlock encrypted disk

**Attacker Actions:**
1. Gain access to stored recovery password
   - Physical theft (paper backup)
   - Digital theft (password manager compromise)
   - Social engineering
2. Boot system, enter recovery password
3. Access data

**System Response:**
- Recovery password is valid credential
- System unlocks normally
- No way to distinguish legitimate from illegitimate use

**Result:** ❌ **ATTACK SUCCEEDS**

**Mitigation Effectiveness:** Depends on password storage security

**Critical Recommendations:**
- Store recovery password in secure location (safe, encrypted USB)
- Don't store in cloud without strong encryption
- Limit copies
- Consider physical security of backup location

## Comparison: With PIN vs. Without PIN

### Current Configuration (No PIN)

**Pros:**
- Fully automated boot
- No user interaction required
- Convenient for headless systems
- Fast boot process

**Cons:**
- Vulnerable to advanced evil maid
- No protection if Secure Boot compromised
- TPM can be queried without user knowledge

**Threat Protection:**
- ✅ Disk theft
- ✅ Partition replacement
- ✅ Basic evil maid
- ⚠️ Advanced evil maid
- ⚠️ TPM extraction

### Alternative Configuration (With PIN)

**Pros:**
- Requires physical presence + knowledge
- Protects against unauthorized TPM unsealing
- Defeats most evil maid attacks
- Stronger security posture

**Cons:**
- Requires PIN entry on every boot
- Not suitable for headless systems
- Slightly slower boot process
- User can forget PIN

**Threat Protection:**
- ✅ Disk theft
- ✅ Partition replacement
- ✅ Basic evil maid
- ✅ Advanced evil maid
- ✅ TPM extraction (much harder)

### Recommendation

**For most corporate environments:** No PIN (current configuration)
- Physical security is adequate
- Convenience is valuable
- Risk of advanced evil maid is low

**For high-security environments:** Add PIN
- Protection against sophisticated attacks
- Defense in depth
- Acceptable inconvenience

**To add PIN post-installation:**
```bash
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+2+7+9 --tpm2-with-pin=true /dev/sda3
sudo nano /etc/crypttab  # Add tpm2-pin=true
sudo update-initramfs -u -k all
```

## Operational Security Recommendations

### Pre-Deployment

1. **BIOS Configuration**
   - ✅ Set strong BIOS/UEFI password
   - ✅ Enable Secure Boot
   - ✅ Enable TPM 2.0
   - ✅ Disable legacy boot modes
   - ✅ Disable USB/network boot (or password-protect)

2. **Hardware**
   - ✅ Verify TPM is present and functioning
   - ✅ Check for BIOS updates (apply before installation)
   - ✅ Document hardware configuration

3. **Configuration**
   - ✅ Use strong SSH keys (Ed25519 or RSA 4096)
   - ✅ Customize usernames (avoid defaults)
   - ✅ Generate unique passwords

### During Deployment

1. **Installation**
   - ✅ Perform in secure location
   - ✅ Verify USB installer authenticity
   - ✅ Note generated recovery password
   - ✅ Test TPM enrollment succeeded

2. **First Boot**
   - ✅ Retrieve and backup recovery password
   - ✅ Verify auto-unlock works
   - ✅ Test SSH access
   - ✅ Apply security updates

3. **Recovery Password Backup**
   - ✅ Print and store in physical safe
   - ✅ Encrypt and store on separate device
   - ✅ Document location in IT inventory
   - ❌ Don't store in plaintext on network
   - ❌ Don't email unencrypted
   - ❌ Don't store in user-accessible location

### Post-Deployment

1. **Monitoring**
   - ✅ Monitor for unexpected reboots
   - ✅ Alert on PCR changes (requires remote attestation)
   - ✅ Log boot events
   - ✅ Track firmware/BIOS updates

2. **Maintenance**
   - ✅ Test recovery password quarterly
   - ✅ Verify TPM enrollment after updates
   - ✅ Check /var/log/tpm2-setup.log periodically
   - ✅ Document any re-enrollment events

3. **Incident Response**
   - ✅ Have procedure for lost/stolen devices
   - ✅ Can remotely disable if network-connected
   - ✅ Report immediately to security team
   - ✅ Consider device compromised if physical access suspected

### Device Handling

1. **Daily Use**
   - ✅ Don't leave device unattended in public
   - ✅ Log out or lock screen when away
   - ✅ Shut down (not sleep) when traveling
   - ✅ Be aware of shoulder surfing

2. **Travel**
   - ✅ Keep device with you (don't check in luggage)
   - ✅ Power off completely at borders
   - ✅ Be aware of hotel room access
   - ✅ Consider device potentially compromised if out of sight

3. **Disposal**
   - ✅ Securely wipe disk before disposal
   - ✅ Use `shred` or physical destruction
   - ✅ Clear TPM before disposal
   - ✅ Document disposal in asset tracking

## Compliance Considerations

### GDPR (Data Protection)

**Requirements:**
- Personal data must be protected "against unauthorised or unlawful processing"
- "Appropriate technical and organisational measures"

**This System:**
- ✅ Provides encryption at rest
- ✅ Prevents unauthorized access to powered-off devices
- ⚠️ Users must protect recovery passwords
- ⚠️ Consider additional controls for sensitive data

### HIPAA (Healthcare)

**Requirements:**
- "Encryption and decryption" (§164.312(a)(2)(iv))
- "Addressable" specification (not required, but must justify alternatives)

**This System:**
- ✅ Implements encryption at rest
- ✅ Access control via TPM
- ⚠️ Recovery password must be protected per HIPAA standards
- ⚠️ Audit logs should be enabled and monitored

### PCI DSS (Payment Card Industry)

**Requirements:**
- Requirement 3.4: "Render PAN unreadable anywhere it is stored"
- Requirement 10: "Track and monitor all access to network resources and cardholder data"

**This System:**
- ✅ Encryption meets Requirement 3.4
- ⚠️ Additional audit logging needed for Requirement 10
- ⚠️ Recovery password storage must meet PCI requirements
- ⚠️ Regular security testing required

### ISO 27001

**Controls:**
- A.10.1.1: Cryptographic controls
- A.11.2: Equipment security

**This System:**
- ✅ Implements cryptographic controls
- ✅ TPM-based key management
- ⚠️ Document in ISMS (Information Security Management System)
- ⚠️ Regular risk assessments required

## Risk Assessment

### Risk Matrix

| Threat | Likelihood | Impact | Risk | Mitigation |
|--------|-----------|--------|------|------------|
| Disk theft | High | High | **HIGH** | ✅ Encrypted |
| Evil maid (basic) | Medium | High | **MEDIUM** | ✅ Secure Boot |
| Evil maid (advanced) | Low | High | **MEDIUM** | ⚠️ Consider PIN |
| TPM extraction | Very Low | High | **LOW** | ⚠️ Acceptable |
| Recovery password theft | Low | High | **MEDIUM** | ⚠️ Secure storage |
| Malware after boot | Medium | High | **MEDIUM** | ⚠️ Additional controls |
| Supply chain | Very Low | Very High | **LOW** | ⚠️ Trusted supplier |

### Residual Risk

After implementing this system, residual risks include:

1. **Advanced evil maid attacks**
   - Sophisticated attackers with resources
   - Mitigation: Add PIN if threat level warrants

2. **Recovery password compromise**
   - Social engineering, insider threats
   - Mitigation: Strong password storage procedures

3. **Post-boot compromise**
   - Malware, vulnerabilities
   - Mitigation: Additional security controls (firewall, IDS, etc.)

4. **Supply chain attacks**
   - Pre-compromised hardware
   - Mitigation: Trusted suppliers, inspection

## Security Checklist

### Essential (Must Implement)

- [ ] Set BIOS password
- [ ] Enable Secure Boot
- [ ] Enable TPM 2.0
- [ ] Backup recovery password securely
- [ ] Test recovery password
- [ ] Apply security updates
- [ ] Disable password SSH authentication
- [ ] Enable firewall

### Recommended (Should Implement)

- [ ] Disable USB boot (or password-protect)
- [ ] Enable audit logging
- [ ] Configure automatic updates
- [ ] Set up intrusion detection
- [ ] Implement backup strategy
- [ ] Document security procedures
- [ ] Train users on physical security

### Optional (Consider for High Security)

- [ ] Add TPM PIN
- [ ] Implement remote attestation
- [ ] Use hardware security keys
- [ ] Enable AppArmor/SELinux
- [ ] Full disk wipe on multiple failed boots
- [ ] Network-based key escrow (Tang)
- [ ] Regular security audits

## Conclusion

This TPM2-based autoinstaller provides **strong protection** against common threats while maintaining **usability**. It is appropriate for:

- Corporate workstations
- Development systems
- Personal devices in secure environments

It is **NOT appropriate** for:

- High-security government/military
- Systems in hostile environments
- Protection against nation-state actors

The system's security can be **enhanced** by:

1. Adding a TPM PIN (most impactful)
2. Implementing remote attestation
3. Strict recovery password procedures
4. Additional post-boot security controls

**Overall Assessment:** This system provides a reasonable balance between security and usability for most corporate and personal use cases. Organizations with higher security requirements should add a PIN and implement additional security controls.

---

**Document Version:** 1.0
**Last Updated:** November 2024
**Next Review:** Quarterly or after significant security events
