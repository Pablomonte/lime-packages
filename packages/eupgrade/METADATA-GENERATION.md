# eupgrade Metadata Generation Guide

This guide explains how to generate JSON metadata files for eupgrade-compatible installers.

## Overview

eupgrade requires JSON metadata files that describe available firmware updates. The `generate-metadata.sh` script automates the creation of these files for LibreRouter ART Fix installers.

## Quick Start

```bash
# 1. Build the installer first
./build-installer.sh /path/to/firmware.bin

# 2. Generate metadata
./generate-metadata.sh librerouter-v1-sysupgrade-installer.sh

# 3. Review output
cat librerouter-librerouter-v1.json
```

## Prerequisites

### Required Tools

- `bash` - Shell execution
- `strings` - Extract strings from binaries (binutils package)
- `sha256sum` - Calculate checksums (coreutils package)
- `stat` - File information (coreutils package)

### Optional Tools

- `usign` - For cryptographic signatures (OpenWRT package or build from source)
- `jq` - For JSON validation in testing

Install on Ubuntu/Debian:
```bash
sudo apt-get install binutils coreutils
```

## Usage

### Basic Usage

```bash
./generate-metadata.sh <installer.sh> [base-url]
```

**Arguments:**
- `installer.sh` - Path to the self-extracting installer script
- `base-url` - (Optional) Base URL where installer will be hosted
  - Default: `http://repo.librerouter.org/art-fix/releases/1.0`

**Output:**
- `librerouter-librerouter-v1.json` - Metadata file
- `librerouter-librerouter-v1.json.sig` - Signature file

### Examples

**Development (local testing):**
```bash
./generate-metadata.sh librerouter-v1-sysupgrade-installer.sh
```

**Production (with custom URL):**
```bash
./generate-metadata.sh \
    librerouter-v1-sysupgrade-installer.sh \
    http://repo.librerouter.org/art-fix/releases/1.0
```

**With real signature:**
```bash
SIGNING_KEY=/path/to/private.key \
    ./generate-metadata.sh librerouter-v1-sysupgrade-installer.sh
```

## How It Works

### 1. Version Extraction

The script uses `strings` to search for `DISTRIB_DESCRIPTION` in the installer file:

```bash
strings installer.sh | grep "^DISTRIB_DESCRIPTION=" | cut -d= -f2
```

This extracts the firmware version from the embedded binary, which looks like:
- `OpenWrt 21.02.3 r16554-1d4dea6d4f`
- `LibreRouterOs 1.5 r0+11434-e93615c947`

### 2. SHA256 Calculation

Calculates the checksum of the complete installer file:

```bash
sha256sum installer.sh | cut -d' ' -f1
```

This ensures integrity when eupgrade downloads the installer.

### 3. JSON Generation

Creates a JSON file with eupgrade-compatible structure:

```json
{
    "metadata-version": 1,
    "images": [
        {
            "name": "installer.sh",
            "type": "installer",
            "download-urls": [
                "http://repo.librerouter.org/art-fix/releases/1.0/installer.sh"
            ],
            "sha256": "abc123..."
        }
    ],
    "board": "librerouter,librerouter-v1",
    "version": "LibreRouterOs 1.5 r0+11434-e93615c947",
    "release-info-url": "https://foro.librerouter.org/art-fix-announcement"
}
```

### 4. Signature Generation

**Mock Signature (default):**
- Creates a placeholder `.sig` file for testing
- eupgrade will show a warning but still work
- **NOT for production use**

**Real Signature (with SIGNING_KEY):**
- Uses `usign` to cryptographically sign the JSON
- Required for production deployment
- Public key must be installed on routers in `/etc/opkg/keys/`

## Deployment Workflow

### Step 1: Build Installer

```bash
cd /home/pablo/repos/lime-dev/repos/lime-packages/packages/eupgrade

# Download latest safe-upgrade if needed
wget https://raw.githubusercontent.com/libremesh/lime-packages/refs/heads/master/packages/safe-upgrade/files/usr/sbin/safe-upgrade \
    -O safe-upgrade-fixed.lua

# Build installer
./build-installer.sh /path/to/librerouter-v1-sysupgrade.bin
```

### Step 2: Generate Metadata

```bash
# Generate with production URL
./generate-metadata.sh \
    librerouter-v1-sysupgrade-installer.sh \
    http://repo.librerouter.org/art-fix/releases/1.0
```

### Step 3: Sign Metadata (Production Only)

**Option A: During generation**
```bash
SIGNING_KEY=/path/to/usign/private.key \
    ./generate-metadata.sh librerouter-v1-sysupgrade-installer.sh
```

**Option B: After generation**
```bash
usign -S \
    -m librerouter-librerouter-v1.json \
    -s /path/to/usign/private.key \
    -x librerouter-librerouter-v1.json.sig
```

### Step 4: Validate

```bash
# Validate JSON syntax
python3 -m json.tool librerouter-librerouter-v1.json

# Verify SHA256
sha256sum librerouter-v1-sysupgrade-installer.sh
# Compare with SHA256 in JSON file

# Verify signature (if signed)
usign -V \
    -m librerouter-librerouter-v1.json \
    -p /path/to/usign/public.key \
    -x librerouter-librerouter-v1.json.sig
```

### Step 5: Upload to Server

```bash
# Upload installer
scp librerouter-v1-sysupgrade-installer.sh \
    user@repo.librerouter.org:/var/www/repo.librerouter.org/art-fix/releases/1.0/

# Upload metadata
scp librerouter-librerouter-v1.json librerouter-librerouter-v1.json.sig \
    user@repo.librerouter.org:/var/www/repo.librerouter.org/lros/api/v1/latest/
```

### Step 6: Verify Deployment

```bash
# Test metadata URL
curl http://repo.librerouter.org/lros/api/v1/latest/librerouter-librerouter-v1.json

# Test installer URL
curl -I http://repo.librerouter.org/art-fix/releases/1.0/librerouter-v1-sysupgrade-installer.sh
```

## Directory Structure on Server

```
/var/www/repo.librerouter.org/
├── art-fix/
│   └── releases/
│       └── 1.0/
│           └── librerouter-art-fix-installer.sh  # The installer binary
│
└── lros/
    └── api/
        └── v1/
            └── latest/
                ├── librerouter-librerouter-v1.json      # Metadata
                └── librerouter-librerouter-v1.json.sig  # Signature
```

## Router Configuration

For routers to discover this metadata, configure eupgrade:

```bash
uci set eupgrade.main.api_url='http://repo.librerouter.org/lros/api/v1/'
uci commit eupgrade
```

eupgrade will then fetch:
```
http://repo.librerouter.org/lros/api/v1/latest/librerouter-librerouter-v1.json
```

## Cryptographic Signatures

### Generating usign Keys (One-Time Setup)

```bash
# Generate key pair
usign -G -s private.key -p public.key -c "LibreRouter ART Fix Release Key"

# Secure private key
chmod 600 private.key

# Distribute public key to routers
# Copy public.key to router's /etc/opkg/keys/
```

### Signing Workflow

```bash
# Sign metadata
usign -S -m librerouter-librerouter-v1.json \
      -s private.key \
      -x librerouter-librerouter-v1.json.sig

# Verify signature
usign -V -m librerouter-librerouter-v1.json \
      -p public.key \
      -x librerouter-librerouter-v1.json.sig
```

### Public Key Distribution

Routers verify signatures using public keys in `/etc/opkg/keys/`:

```bash
# On router
ls -la /etc/opkg/keys/
# Should contain public key file matching the signing key
```

If the public key is not installed, eupgrade will reject the update with a signature verification error.

## Troubleshooting

### "ERROR: Could not find version string in installer"

**Cause:** The installer doesn't contain an embedded firmware with `/etc/openwrt_release`

**Solution:**
1. Verify installer was built correctly with `build-installer.sh`
2. Check that firmware binary was concatenated properly
3. Test manually: `strings installer.sh | grep DISTRIB_DESCRIPTION`

### "WARNING: usign command not found"

**Cause:** `usign` tool not installed

**Solution:**
- For testing: Use mock signature (default)
- For production: Install usign or build from source
  - Source: https://git.openwrt.org/project/usign.git

### "ERROR: Signing key not found"

**Cause:** `SIGNING_KEY` environment variable points to non-existent file

**Solution:**
1. Verify key path: `ls -la $SIGNING_KEY`
2. Generate keys if needed (see Cryptographic Signatures section)
3. Or omit `SIGNING_KEY` to use mock signature for testing

### SHA256 Mismatch on Router

**Cause:** Installer file was modified after metadata generation

**Solution:**
1. Regenerate metadata after any installer changes
2. Verify SHA256 after upload: `sha256sum installer.sh`
3. Never edit the installer file after generating metadata

## Testing Without Production Server

### Local Test Server

```bash
# Start simple HTTP server in eupgrade directory
cd /home/pablo/repos/lime-dev/repos/lime-packages/packages/eupgrade
python3 -m http.server 8000

# Generate metadata with local URL
./generate-metadata.sh installer.sh http://localhost:8000

# Configure router to use local server
# (on router)
uci set eupgrade.main.api_url='http://192.168.1.100:8000/'
uci commit eupgrade
```

### Manual Testing on Router

```bash
# Copy metadata to router
scp librerouter-librerouter-v1.json* root@192.168.1.1:/tmp/eupgrades/firmware_latest.json

# Check if eupgrade detects it
# (on router)
ubus call eupgrade is_new_version_available
```

## Security Considerations

1. **Never deploy with mock signatures in production**
   - Mock signatures allow anyone to create fake updates
   - Always use real usign signatures for production releases

2. **Protect private keys**
   - Store offline in secure location
   - Use `chmod 600` permissions
   - Never commit to version control

3. **Verify uploads**
   - Always verify SHA256 after uploading to server
   - Test download and signature verification before announcing release

4. **Use HTTPS for metadata**
   - Prevents man-in-the-middle attacks
   - Recommended: `https://repo.librerouter.org/...`

5. **Version string validation**
   - Script uses exact version from firmware
   - Version must differ from router's current version to trigger update

## Related Documentation

- [README-INSTALLER.md](README-INSTALLER.md) - Installer build process
- [eupgrade source](files/usr/lib/lua/eupgrade.lua) - How routers consume metadata
- [usign documentation](https://git.openwrt.org/project/usign.git) - Signature tool

## Support

For issues or questions:
- GitHub Issues: https://github.com/libremesh/lime-packages/issues
- Forum: https://foro.librerouter.org/
