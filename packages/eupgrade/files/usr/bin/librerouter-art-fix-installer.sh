#!/bin/sh
# shellcheck shell=ash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# LibreRouter ART Case Fix Self-Extracting Installer
# Fixes uppercase ART partition in U-Boot environment before firmware upgrade
#
# This installer:
# 1. Verifies board is LibreRouter V1
# 2. Extracts and installs updated safe-upgrade
# 3. Detects next boot partition
# 4. Fixes uppercase ART -> lowercase art in boot_N parameter
# 5. Extracts embedded firmware image
# 6. Executes safe-upgrade
#
# Integration with eupgrade:
# - Status: /tmp/upgrade-installer-status ('failed' | 'success' | 'running')
# - Error: /tmp/upgrade-installer-error-mesage
# - Log: /tmp/upgrade-installer.log (via stderr redirect)

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Constants (readonly for immutability)
readonly BOARD_NAME_FILE="/tmp/sysinfo/board_name"
readonly SAFE_UPGRADE_PATH="/usr/sbin/safe-upgrade"
readonly SAFE_UPGRADE_TEMP="/tmp/safe-upgrade-installer.lua"
readonly IMAGE_PATH="/tmp/firmware-installer.bin"
readonly STATUS_FILE="/tmp/upgrade-installer-status"
readonly ERROR_FILE="/tmp/upgrade-installer-error-mesage"  # Typo matches eupgrade
readonly LOG_PREFIX="[ART-FIX-INSTALLER]"
readonly MIN_TMP_SPACE_KB=10240  # ~10MB

# Cleanup temporary files on exit
# shellcheck disable=SC2317
cleanup() {
    rm -f "$SAFE_UPGRADE_TEMP" "$IMAGE_PATH"
}
trap cleanup EXIT

# Logging functions
log() {
    echo "$LOG_PREFIX $1" >&2
}

error_exit() {
    local message="$1"
    log "ERROR: $message"
    echo "failed" > "$STATUS_FILE"
    echo "$message" > "$ERROR_FILE"
    exit 1
}

# Check required commands and configuration
check_prerequisites() {
    log "Checking prerequisites..."

    # Verificar comandos requeridos (safe-upgrade será instalado por este script)
    for cmd in fw_printenv fw_setenv tail awk lua; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error_exit "Required command not found: $cmd"
        fi
    done

    # Verificar fw_env.config (pattern from safe-upgrade:94)
    if [ ! -f /etc/fw_env.config ]; then
        error_exit "/etc/fw_env.config does not exist"
    fi

    log "Prerequisites OK"
}

# Verify board is LibreRouter V1
verify_board() {
    log "Verifying board type..."

    if [ ! -f "$BOARD_NAME_FILE" ]; then
        error_exit "Board name file not found: $BOARD_NAME_FILE"
    fi

    local board_name
    board_name=$(tr -d '\n' < "$BOARD_NAME_FILE")

    # Pattern from safe-upgrade:162-176
    case "$board_name" in
        *librerouter-v1*)
            log "Board verified: $board_name"
            ;;
        *)
            error_exit "Unsupported board: $board_name (expected librerouter-v1)"
            ;;
    esac
}

# Detect next boot partition
detect_partitions() {
    log "Detecting next boot partition..."

    # Pattern from safe-upgrade:108-115
    # Si /proc/mtd contiene "fw2" → current=1, next=2; sino current=2, next=1
    if grep -q "fw2" /proc/mtd; then
        NEXT_PARTITION=2
    else
        NEXT_PARTITION=1
    fi

    log "Next boot partition will be: $NEXT_PARTITION"
}

# Fix ART case in boot_N U-Boot parameter
fix_art_case() {
    log "Checking boot_$NEXT_PARTITION for ART case issue..."

    local boot_var="boot_$NEXT_PARTITION"
    local boot_value
    # Capture fw_printenv output, handle error gracefully (set -e won't exit)
    boot_value=$(fw_printenv -n "$boot_var" 2>&1 || true)

    # Verificar si variable existe (pattern safe-upgrade:75-85)
    if echo "$boot_value" | grep -q "## Error:"; then
        log "WARNING: $boot_var not found in U-Boot environment"
        log "Skipping ART fix (will be created with correct case during upgrade)"
        return 0
    fi

    # Also check for empty output (another way fw_printenv indicates missing var)
    if [ -z "$boot_value" ]; then
        log "WARNING: $boot_var is empty or not set in U-Boot environment"
        log "Skipping ART fix (will be created with correct case during upgrade)"
        return 0
    fi

    # Verificar si contiene ART en mayúsculas
    if ! echo "$boot_value" | grep -q "mtdparts=.*ART"; then
        log "No uppercase ART found - already correct"
        return 0
    fi

    log "Found uppercase ART in $boot_var, fixing..."

    # Reemplazar ART con art (solo en contexto mtdparts)
    # Pattern: ...128k(ART)... → ...128k(art)...
    local fixed_value
    fixed_value=$(echo "$boot_value" | sed 's/\([0-9]k\)(ART)/\1(art)/g')

    if [ "$boot_value" = "$fixed_value" ]; then
        error_exit "Failed to fix ART case - sed replacement didn't work"
    fi

    # Aplicar el fix usando fw_setenv -s - (atomic)
    log "Applying fix to $boot_var..."
    if ! echo "$boot_var $fixed_value" | fw_setenv -s -; then
        error_exit "Failed to set U-Boot environment variable: $boot_var"
    fi

    # Verificar que el cambio se aplicó
    local verify_value
    verify_value=$(fw_printenv -n "$boot_var" 2>/dev/null)

    if echo "$verify_value" | grep -q "mtdparts=.*ART"; then
        error_exit "Verification failed: uppercase ART still present after fix"
    fi

    log "Successfully fixed ART case in $boot_var"
}

# Extract and install safe-upgrade from embedded section
extract_and_install_safe_upgrade() {
    log "Extracting embedded safe-upgrade..."

    # Find archive marker and read safe-upgrade size
    local archive_line
    archive_line=$(grep -n "^# __ARCHIVE_BELOW__$" "$0" | head -n 1 | cut -d: -f1)

    if [ -z "$archive_line" ]; then
        error_exit "Could not find __ARCHIVE_BELOW__ marker in installer"
    fi

    # Read safe-upgrade size from next line
    local safe_upgrade_size
    safe_upgrade_size=$(sed -n "$((archive_line + 1))p" "$0" | grep "SAFE_UPGRADE_SIZE=" | cut -d= -f2)

    if [ -z "$safe_upgrade_size" ]; then
        error_exit "Could not find SAFE_UPGRADE_SIZE in installer"
    fi

    log "safe-upgrade size: $safe_upgrade_size bytes"

    # Calculate byte offset: skip to line after size declaration
    local skip_lines=$((archive_line + 1))
    local archive_start
    archive_start=$(head -n "$skip_lines" "$0" | wc -c)

    log "Extracting from byte offset $archive_start..."

    # BusyBox workaround: Copy script first (can't read from executing script)
    local installer_copy
    installer_copy=$(mktemp)
    cp "$0" "$installer_copy"

    # Extract safe-upgrade using dd with skip and count from the temp copy
    # bs=1 is slow but reliable in BusyBox; avoid tail|head pipes which hang
    dd if="$installer_copy" bs=1 skip="$archive_start" count="$safe_upgrade_size" of="$SAFE_UPGRADE_TEMP" 2>/dev/null

    # Cleanup copy
    rm "$installer_copy"

    log "Extraction completed, verifying..."

    if [ ! -f "$SAFE_UPGRADE_TEMP" ]; then
        error_exit "Failed to extract safe-upgrade to $SAFE_UPGRADE_TEMP"
    fi

    local extracted_size
    extracted_size=$(wc -c < "$SAFE_UPGRADE_TEMP" 2>/dev/null || echo "0")

    # Verify extraction integrity
    if [ "$extracted_size" -ne "$safe_upgrade_size" ]; then
        error_exit "Extraction failed: expected $safe_upgrade_size bytes, got $extracted_size bytes"
    fi

    if [ "$extracted_size" -lt 1000 ]; then
        error_exit "Extracted safe-upgrade too small: $extracted_size bytes (expected ~17KB)"
    fi

    log "Verified: extracted $extracted_size bytes (matches expected size)"

    # Verify it's valid Lua script
    if ! head -n 1 "$SAFE_UPGRADE_TEMP" | grep -q "^#!/"; then
        error_exit "Extracted file doesn't look like a valid script (missing shebang)"
    fi

    # Instalar safe-upgrade
    log "Installing safe-upgrade to $SAFE_UPGRADE_PATH..."

    # Backup existing if present
    if [ -f "$SAFE_UPGRADE_PATH" ]; then
        log "Backing up existing safe-upgrade to ${SAFE_UPGRADE_PATH}.bak"
        cp "$SAFE_UPGRADE_PATH" "${SAFE_UPGRADE_PATH}.bak"
    fi

    # Install new version
    cp "$SAFE_UPGRADE_TEMP" "$SAFE_UPGRADE_PATH"
    chmod +x "$SAFE_UPGRADE_PATH"

    # Verify installation
    if ! "$SAFE_UPGRADE_PATH" --help >/dev/null 2>&1 && \
       ! lua "$SAFE_UPGRADE_PATH" --help >/dev/null 2>&1; then
        error_exit "safe-upgrade installation verification failed"
    fi

    log "safe-upgrade installed successfully"
}

# Re-bootstrap safe-upgrade to fix any previous incorrect bootstrap
bootstrap_safe_upgrade() {
    log "Re-bootstrapping safe-upgrade with fixed templates..."

    # This ensures boot_1 and boot_2 are recreated with correct "art" template
    # even if a previous buggy version of safe-upgrade already did bootstrap
    # --force flag overwrites existing boot variables
    if ! "$SAFE_UPGRADE_PATH" bootstrap --force 2>&1 | grep -q -e "success" -e "Boot variables set"; then
        log "WARNING: Bootstrap output didn't confirm success"
        log "Will proceed with manual ART case fix as fallback"
        return 0  # Not critical, fix_art_case will handle it
    fi

    log "Bootstrap completed - boot parameters recreated with correct templates"
}

# Extract embedded firmware from end of this script
extract_firmware() {
    log "Checking available space in /tmp..."

    local available_kb
    available_kb=$(df /tmp | tail -n 1 | awk '{print $4}')

    if [ "$available_kb" -lt "$MIN_TMP_SPACE_KB" ]; then
        error_exit "Insufficient space in /tmp: ${available_kb}KB available, ${MIN_TMP_SPACE_KB}KB required"
    fi

    log "Extracting embedded firmware image..."

    # Find archive marker and calculate firmware offset
    local archive_line
    archive_line=$(grep -n "^# __ARCHIVE_BELOW__$" "$0" | head -n 1 | cut -d: -f1)

    # Read safe-upgrade size
    local safe_upgrade_size
    safe_upgrade_size=$(sed -n "$((archive_line + 1))p" "$0" | grep "SAFE_UPGRADE_SIZE=" | cut -d= -f2)

    # Calculate byte offset: skip archive header + safe-upgrade
    local skip_lines=$((archive_line + 1))
    local archive_start
    archive_start=$(head -n "$skip_lines" "$0" | wc -c)
    local firmware_start=$((archive_start + safe_upgrade_size))

    log "Firmware starts at byte offset $firmware_start"

    # BusyBox workaround: Copy script first (can't read from executing script)
    local installer_copy
    installer_copy=$(mktemp)
    cp "$0" "$installer_copy"

    # Extract binary firmware using dd from the copy
    dd if="$installer_copy" bs=1 skip="$firmware_start" of="$IMAGE_PATH" 2>/dev/null

    # Cleanup copy
    rm "$installer_copy"

    log "Firmware extraction completed, verifying..."

    if [ ! -f "$IMAGE_PATH" ]; then
        error_exit "Failed to extract firmware image to $IMAGE_PATH"
    fi

    # Verify extraction and size
    local image_size
    image_size=$(wc -c < "$IMAGE_PATH" 2>/dev/null || echo "0")

    if [ "$image_size" -lt 1048576 ]; then
        error_exit "Extracted firmware too small: $image_size bytes (expected at least 1MB)"
    fi

    # Verify it looks like a firmware image (check magic bytes if possible)
    local file_type
    if command -v file >/dev/null 2>&1; then
        file_type=$(file "$IMAGE_PATH" 2>/dev/null || echo "unknown")
        log "Firmware file type: $file_type"
    fi

    log "Verified: extracted firmware image ($image_size bytes)"
}

# Execute safe-upgrade with extracted firmware
execute_upgrade() {
    log "Initiating safe-upgrade..."

    # safe-upgrade ya fue instalado por extract_and_install_safe_upgrade()
    # Preserva configuración por defecto (sin flag -n)
    log "Using safe-upgrade upgrade $IMAGE_PATH"
    if ! "$SAFE_UPGRADE_PATH" upgrade "$IMAGE_PATH"; then
        error_exit "Upgrade command failed"
    fi

    log "Upgrade initiated successfully"
    echo "success" > "$STATUS_FILE"
}

# Main execution flow
main() {
    log "Starting LibreRouter ART case fix installer..."

    # Status inicial
    echo "running" > "$STATUS_FILE"

    # Ejecutar pasos en orden
    check_prerequisites
    verify_board
    extract_and_install_safe_upgrade
    bootstrap_safe_upgrade
    detect_partitions
    fix_art_case
    extract_firmware
    execute_upgrade

    log "Installer completed successfully"
}

# Run main function
main

# Archive section (build-installer.sh will replace these markers)
exit 0
# __ARCHIVE_BELOW__
# SAFE_UPGRADE_SIZE=0
