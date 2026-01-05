#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Generate eupgrade metadata for LibreRouter ART Fix Installer
# Extracts version from embedded firmware and creates JSON + signature
#
# Usage: ./generate-metadata.sh <installer.sh> [base-url]
# Output: librerouter-librerouter-v1.json + .sig
#
# Environment Variables:
#   SIGNING_KEY - Path to usign private key for real signatures (optional)
#
# Examples:
#   ./generate-metadata.sh librerouter-v1-sysupgrade-installer.sh
#   ./generate-metadata.sh installer.sh http://custom.url/releases/1.0
#   SIGNING_KEY=/path/to/key.priv ./generate-metadata.sh installer.sh

set -euo pipefail

# Configuration
readonly BOARD_SLUG="librerouter-librerouter-v1"
readonly BOARD_NAME="librerouter,librerouter-v1"
readonly DEFAULT_BASE_URL="http://repo.librerouter.org/art-fix/releases/1.0"
readonly DEFAULT_RELEASE_INFO_URL="https://foro.librerouter.org/art-fix-announcement"

# Input validation
readonly INSTALLER_FILE="${1:-}"
readonly BASE_URL="${2:-$DEFAULT_BASE_URL}"

# Output files
readonly JSON_FILE="${BOARD_SLUG}.json"
readonly SIG_FILE="${JSON_FILE}.sig"

# Extract firmware version from installer using strings
# Supports both modern JSON metadata and legacy DISTRIB_DESCRIPTION formats
extract_firmware_version_simple() {
    local installer="$1"

    echo "Extracting version from installer using string search..." >&2

    # Method 1: Try modern OpenWRT JSON metadata format (since ~2019)
    # Format: {"metadata_version": "1.1", "version": {"dist": "...", "version": "...", "revision": "..."}}
    local json_metadata
    json_metadata=$(strings "$installer" | grep -m1 '"metadata_version".*"version".*"dist"' || echo "")

    if [ -n "$json_metadata" ]; then
        echo "Found OpenWRT JSON metadata format" >&2

        # Extract version components using grep and sed
        # This avoids dependency on jq
        local dist version_num revision

        dist=$(echo "$json_metadata" | grep -o '"dist"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
        version_num=$(echo "$json_metadata" | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/' | head -1)
        revision=$(echo "$json_metadata" | grep -o '"revision"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')

        if [ -n "$dist" ] && [ -n "$version_num" ] && [ -n "$revision" ]; then
            local version="${dist} ${version_num} ${revision}"
            echo "Extracted version: $version" >&2
            echo "$version"
            return
        else
            echo "WARNING: Found JSON metadata but failed to parse version components" >&2
        fi
    fi

    # Method 2: Fallback to legacy DISTRIB_DESCRIPTION format
    echo "Trying legacy DISTRIB_DESCRIPTION format..." >&2
    local version
    version=$(strings "$installer" | \
              grep -m1 "^DISTRIB_DESCRIPTION=" | \
              cut -d= -f2 | tr -d "'\"" || echo "")

    if [ -n "$version" ]; then
        echo "Extracted version: $version" >&2
        echo "$version"
        return
    fi

    # No version found with either method
    echo "ERROR: Could not find version string in installer" >&2
    echo "Tried:" >&2
    echo "  1. OpenWRT JSON metadata (modern format)" >&2
    echo "  2. DISTRIB_DESCRIPTION= (legacy format)" >&2
    exit 1
}

# Calculate SHA256 checksum of a file
calculate_sha256() {
    local file="$1"
    sha256sum "$file" | cut -d' ' -f1
}

# Generate JSON metadata file
generate_json_metadata() {
    local installer_name="$1"
    local version="$2"
    local sha256="$3"
    local base_url="$4"

    # Build download URL
    local download_url="${base_url}/${installer_name}"

    # Generate JSON (using heredoc for proper formatting)
    cat > "$JSON_FILE" <<EOF
{
    "metadata-version": 1,
    "images": [
        {
            "name": "${installer_name}",
            "type": "installer",
            "download-urls": [
                "${download_url}"
            ],
            "sha256": "${sha256}"
        }
    ],
    "board": "${BOARD_NAME}",
    "version": "${version}",
    "release-info-url": "${DEFAULT_RELEASE_INFO_URL}"
}
EOF

    echo "Generated: $JSON_FILE" >&2
}

# Generate mock signature file (for testing without real keys)
generate_mock_signature() {
    local json_file="$1"

    echo "Generating MOCK signature (replace with real usign signature before production)" >&2

    # Create mock signature file
    # Format mimics usign signature structure but is not cryptographically valid
    cat > "$SIG_FILE" <<'EOF'
untrusted comment: MOCK SIGNATURE - REPLACE WITH REAL USIGN SIGNATURE
RWS/MOCK/SIGNATURE/DATA/BASE64ENCODED/PLACEHOLDER/NOT/VALID
EOF

    echo "Generated: $SIG_FILE (MOCK - NOT FOR PRODUCTION)" >&2
    echo "" >&2
    echo "To generate real signature, use:" >&2
    echo "  usign -S -m $json_file -s /path/to/private.key -x $SIG_FILE" >&2
    echo "Or set SIGNING_KEY environment variable and re-run this script" >&2
}

# Generate real usign signature if keys are available
generate_real_signature() {
    local json_file="$1"
    local signing_key="${SIGNING_KEY:-}"

    if [ -z "$signing_key" ]; then
        echo "INFO: No signing key provided (set SIGNING_KEY env var for real signature)" >&2
        generate_mock_signature "$json_file"
        return
    fi

    if [ ! -f "$signing_key" ]; then
        echo "WARNING: Signing key not found: $signing_key" >&2
        generate_mock_signature "$json_file"
        return
    fi

    echo "Generating real usign signature..." >&2

    # Generate signature using usign
    if command -v usign >/dev/null 2>&1; then
        if usign -S -m "$json_file" -s "$signing_key" -x "$SIG_FILE"; then
            echo "Generated: $SIG_FILE (signed with $signing_key)" >&2
        else
            echo "ERROR: usign signature generation failed" >&2
            generate_mock_signature "$json_file"
        fi
    else
        echo "WARNING: usign command not found" >&2
        echo "Install usign package to generate real signatures" >&2
        generate_mock_signature "$json_file"
    fi
}

# Print usage information
print_usage() {
    cat <<EOF
Usage: $0 <installer.sh> [base-url]

Generate eupgrade-compatible JSON metadata for LibreRouter ART Fix installer.

Arguments:
  installer.sh  Path to the self-extracting installer script
  base-url      Base URL where installer will be hosted (optional)
                Default: $DEFAULT_BASE_URL

Output:
  ${BOARD_SLUG}.json     - Metadata for eupgrade
  ${BOARD_SLUG}.json.sig - Signature file (mock by default)

Environment Variables:
  SIGNING_KEY   Path to usign private key for real signatures

Examples:
  $0 librerouter-v1-sysupgrade-installer.sh
  $0 librerouter-v1-sysupgrade-installer.sh http://custom.url/path
  SIGNING_KEY=/etc/usign/key.priv $0 installer.sh

For deployment instructions, see METADATA-GENERATION.md
EOF
}

# Main execution flow
main() {
    echo "========================================"
    echo "LibreRouter ART Fix Metadata Generator"
    echo "========================================"
    echo ""

    # Validate inputs
    if [ -z "$INSTALLER_FILE" ]; then
        print_usage
        exit 1
    fi

    if [ ! -f "$INSTALLER_FILE" ]; then
        echo "ERROR: Installer file not found: $INSTALLER_FILE"
        echo ""
        print_usage
        exit 1
    fi

    # Check for required commands
    for cmd in strings sha256sum; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "ERROR: Required command not found: $cmd"
            echo "Please install the required package"
            exit 1
        fi
    done

    echo "Input:      $INSTALLER_FILE"
    echo "Size:       $(stat -c %s "$INSTALLER_FILE") bytes"
    echo "Board slug: $BOARD_SLUG"
    echo "Base URL:   $BASE_URL"
    echo ""

    # Extract version from embedded firmware
    echo "Step 1: Extracting firmware version..."
    local version
    version=$(extract_firmware_version_simple "$INSTALLER_FILE")
    echo "Version:    $version"
    echo ""

    # Calculate SHA256 of complete installer
    echo "Step 2: Calculating SHA256..."
    local sha256
    sha256=$(calculate_sha256 "$INSTALLER_FILE")
    echo "SHA256:     $sha256"
    echo ""

    # Generate JSON metadata
    echo "Step 3: Generating JSON metadata..."
    local installer_name
    installer_name=$(basename "$INSTALLER_FILE")
    generate_json_metadata "$installer_name" "$version" "$sha256" "$BASE_URL"
    echo ""

    # Generate signature
    echo "Step 4: Generating signature..."
    generate_real_signature "$JSON_FILE"
    echo ""

    echo "========================================"
    echo "Success!"
    echo "========================================"
    echo "Generated files:"
    echo "  - $JSON_FILE ($(stat -c %s "$JSON_FILE") bytes)"
    echo "  - $SIG_FILE ($(stat -c %s "$SIG_FILE") bytes)"
    echo ""
    echo "Next steps:"
    echo "  1. Review the JSON file:"
    echo "     cat $JSON_FILE"
    echo ""
    echo "  2. Validate JSON syntax (optional):"
    echo "     python3 -m json.tool $JSON_FILE"
    echo ""
    echo "  3. Replace mock signature with real usign signature (if needed):"
    echo "     usign -S -m $JSON_FILE -s /path/to/private.key -x $SIG_FILE"
    echo ""
    echo "  4. Upload to repo.librerouter.org:"
    echo "     # Installer:"
    echo "     scp ${installer_name} user@repo.librerouter.org:/var/www/repo.librerouter.org/art-fix/releases/1.0/"
    echo ""
    echo "     # Metadata:"
    echo "     scp $JSON_FILE $SIG_FILE user@repo.librerouter.org:/var/www/repo.librerouter.org/lros/api/v1/latest/"
    echo ""
    echo "  5. Verify upload:"
    echo "     curl http://repo.librerouter.org/lros/api/v1/latest/$JSON_FILE"
    echo ""
}

main
