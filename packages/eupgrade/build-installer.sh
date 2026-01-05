#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Build Self-Extracting Installer
# Creates a self-extracting installer by concatenating:
#   1. Installer script
#   2. safe-upgrade (updated version)
#   3. Sysupgrade firmware image
#
# Usage: ./build-installer.sh <firmware-image.bin>
# Output: <firmware-image>-installer.sh

set -euo pipefail

readonly SCRIPT_FILE="files/usr/bin/librerouter-art-fix-installer.sh"
readonly SAFE_UPGRADE_FILE="safe-upgrade-fixed.lua"
readonly FIRMWARE_IMAGE="$1"

# Cleanup on exit
cleanup() {
    [ -n "${TEMP_SCRIPT:-}" ] && rm -f "$TEMP_SCRIPT"
}
trap cleanup EXIT

# Validate inputs
if [ -z "$FIRMWARE_IMAGE" ]; then
    echo "Usage: $0 <firmware-image.bin>"
    echo ""
    echo "Example:"
    echo "  $0 librerouter-v1-sysupgrade.bin"
    echo ""
    echo "Creates: librerouter-v1-sysupgrade-installer.sh"
    echo ""
    echo "Note: Requires safe-upgrade-fixed.lua to be present"
    echo "      Download with: wget https://raw.githubusercontent.com/libremesh/lime-packages/refs/heads/master/packages/safe-upgrade/files/usr/sbin/safe-upgrade -O safe-upgrade-fixed.lua"
    exit 1
fi

if [ ! -f "$SCRIPT_FILE" ]; then
    echo "Error: Script file not found: $SCRIPT_FILE"
    echo "Make sure you run this from the eupgrade package directory"
    exit 1
fi

if [ ! -f "$SAFE_UPGRADE_FILE" ]; then
    echo "Error: safe-upgrade file not found: $SAFE_UPGRADE_FILE"
    echo ""
    echo "Download it with:"
    echo "  wget https://raw.githubusercontent.com/libremesh/lime-packages/refs/heads/master/packages/safe-upgrade/files/usr/sbin/safe-upgrade -O safe-upgrade-fixed.lua"
    exit 1
fi

if [ ! -f "$FIRMWARE_IMAGE" ]; then
    echo "Error: Firmware image not found: $FIRMWARE_IMAGE"
    exit 1
fi

# Generate output filename
readonly OUTPUT_FILE="${FIRMWARE_IMAGE%.bin}-installer.sh"

echo "========================================"
echo "Building Self-Extracting Installer"
echo "========================================"
echo "Script:       $SCRIPT_FILE"
echo "safe-upgrade: $SAFE_UPGRADE_FILE ($(stat -c %s "$SAFE_UPGRADE_FILE") bytes)"
echo "Firmware:     $FIRMWARE_IMAGE ($(stat -c %s "$FIRMWARE_IMAGE") bytes)"
echo "Output:       $OUTPUT_FILE"
echo ""

# Create temporary file without the markers
TEMP_SCRIPT=$(mktemp)
# Remove the marker lines from the end of the script
head -n -2 "$SCRIPT_FILE" > "$TEMP_SCRIPT"

# Calculate safe-upgrade size for extraction metadata
SAFE_UPGRADE_SIZE=$(stat -c %s "$SAFE_UPGRADE_FILE")

# Concatenate: script (without markers) + embedded offsets + safe-upgrade + firmware
{
    cat "$TEMP_SCRIPT"
    echo "exit 0"
    echo "# __ARCHIVE_BELOW__"
    echo "# SAFE_UPGRADE_SIZE=$SAFE_UPGRADE_SIZE"
    cat "$SAFE_UPGRADE_FILE"
    cat "$FIRMWARE_IMAGE"
} > "$OUTPUT_FILE"

# Make executable
chmod +x "$OUTPUT_FILE"

echo "========================================"
echo "Success!"
echo "========================================"
echo "Created: $OUTPUT_FILE"
echo "  Script size:       $(stat -c %s "$SCRIPT_FILE") bytes"
echo "  safe-upgrade size: $(stat -c %s "$SAFE_UPGRADE_FILE") bytes"
echo "  Firmware size:     $(stat -c %s "$FIRMWARE_IMAGE") bytes"
echo "  Total size:        $(stat -c %s "$OUTPUT_FILE") bytes"
echo ""
echo "Upload this installer to eupgrade and it will:"
echo "  1. Verify board is LibreRouter V1"
echo "  2. Extract and install updated safe-upgrade"
echo "  3. Re-bootstrap safe-upgrade with correct templates"
echo "  4. Fix ART case in next boot partition (double-check)"
echo "  5. Extract and flash firmware"
echo "  6. Reboot into upgraded system"
