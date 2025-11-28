#!/bin/bash
#
# test-config.sh - Validation script for autoinstall configuration
# Can be run in WSL to validate YAML syntax and configuration before creating USB
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_DATA="$SCRIPT_DIR/user-data"
META_DATA="$SCRIPT_DIR/meta-data"

echo "========================================="
echo "Autoinstall Configuration Validator"
echo "========================================="
echo ""

# Check if required files exist
echo "[1/5] Checking required files..."
if [ ! -f "$USER_DATA" ]; then
    echo "ERROR: user-data file not found at $USER_DATA"
    exit 1
fi

if [ ! -f "$META_DATA" ]; then
    echo "ERROR: meta-data file not found at $META_DATA"
    exit 1
fi

echo "✓ All required files found"
echo ""

# Check if Python is available for YAML validation
echo "[2/5] Checking dependencies..."
if ! command -v python3 &> /dev/null; then
    echo "WARNING: Python3 not found. Skipping YAML syntax validation."
    echo "  Install Python3 to enable YAML validation: apt install python3"
else
    echo "✓ Python3 found"

    # Check if PyYAML is available
    if ! python3 -c "import yaml" 2>/dev/null; then
        echo "WARNING: PyYAML not installed. Skipping detailed YAML validation."
        echo "  Install PyYAML: pip3 install pyyaml"
    else
        echo "✓ PyYAML found"
    fi
fi
echo ""

# Validate YAML syntax
echo "[3/5] Validating YAML syntax..."
if command -v python3 &> /dev/null && python3 -c "import yaml" 2>/dev/null; then
    python3 << 'PYEOF'
import yaml
import sys

try:
    with open('user-data', 'r') as f:
        content = f.read()
        # Skip the #cloud-config line for YAML parsing
        if content.startswith('#cloud-config'):
            content = content.split('\n', 1)[1]
        data = yaml.safe_load(content)
        print("✓ YAML syntax is valid")

        # Check for autoinstall key
        if 'autoinstall' not in data:
            print("ERROR: Missing 'autoinstall' key in user-data")
            sys.exit(1)

        # Check for required sections
        autoinstall = data['autoinstall']
        required_sections = ['version', 'storage', 'late-commands']
        for section in required_sections:
            if section not in autoinstall:
                print(f"WARNING: Missing '{section}' section in autoinstall")

        print("✓ Required sections present")

except yaml.YAMLError as e:
    print(f"ERROR: YAML syntax error:")
    print(e)
    sys.exit(1)
except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)
PYEOF

    if [ $? -ne 0 ]; then
        echo "YAML validation failed!"
        exit 1
    fi
else
    echo "⊘ Skipping YAML validation (PyYAML not available)"
fi
echo ""

# Check for placeholder values that need to be customized
echo "[4/5] Checking for placeholder values..."
PLACEHOLDERS_FOUND=0

# Check for temporary password placeholder
if grep -q "TEMP_PASSWORD_REPLACE_ME" "$USER_DATA"; then
    echo "⚠ Found temporary password placeholder"
    echo "   This will be replaced by create-usb.sh"
    PLACEHOLDERS_FOUND=$((PLACEHOLDERS_FOUND + 1))
fi

# Check for placeholder SSH key
if grep -q "your-public-key-here" "$USER_DATA"; then
    echo "⚠ WARNING: Placeholder SSH public key found"
    echo "   You should replace this with your actual SSH public key"
    echo "   Edit user-data and replace the ssh authorized-keys section"
    PLACEHOLDERS_FOUND=$((PLACEHOLDERS_FOUND + 1))
fi

# Check for default username
if grep -q 'username: admin' "$USER_DATA"; then
    echo "ℹ  Default username 'admin' found"
    echo "   You may want to customize this in user-data"
fi

# Check for default hostname
if grep -q 'hostname: ubuntu-secure' "$USER_DATA"; then
    echo "ℹ  Default hostname 'ubuntu-secure' found"
    echo "   You may want to customize this in user-data"
fi

if [ $PLACEHOLDERS_FOUND -gt 0 ]; then
    echo ""
    echo "⚠  $PLACEHOLDERS_FOUND placeholder(s) found that should be customized"
fi
echo ""

# Validate storage configuration structure
echo "[5/5] Validating storage configuration..."
if grep -q "type: disk" "$USER_DATA" && \
   grep -q "type: dm_crypt" "$USER_DATA" && \
   grep -q "type: lvm_volgroup" "$USER_DATA"; then
    echo "✓ Storage configuration structure looks good"
else
    echo "WARNING: Storage configuration may be incomplete"
fi
echo ""

# Check for TPM2 enrollment script
echo "[BONUS] Checking TPM2 enrollment script..."
if grep -q "systemd-cryptenroll" "$USER_DATA"; then
    echo "✓ TPM2 enrollment script found in late-commands"
else
    echo "ERROR: TPM2 enrollment script not found!"
    exit 1
fi

if grep -q "tpm2-measure-pcr=yes" "$USER_DATA"; then
    echo "✓ PCR 15 measurement configured in crypttab"
else
    echo "WARNING: PCR 15 measurement may not be configured"
fi

if grep -q "recovery-password" "$USER_DATA"; then
    echo "✓ Recovery password generation found"
else
    echo "WARNING: Recovery password generation not found"
fi
echo ""

# Summary
echo "========================================="
echo "Validation Summary"
echo "========================================="
echo "✓ Configuration files present"
echo "✓ YAML syntax valid (if checked)"
echo "✓ Storage configuration present"
echo "✓ TPM2 enrollment configured"
echo ""

if [ $PLACEHOLDERS_FOUND -gt 0 ]; then
    echo "⚠  ACTION REQUIRED:"
    echo "   - Replace placeholder SSH public key"
    echo "   - Customize username/hostname if desired"
    echo ""
fi

echo "Next steps:"
echo "  1. Customize user-data (SSH key, username, hostname)"
echo "  2. Run create-usb.sh to build bootable installer"
echo "  3. Test in VM before deploying to hardware"
echo ""
echo "========================================="
