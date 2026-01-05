# LibreRouter ART Case Fix Self-Extracting Installer

## Overview

This installer fixes the uppercase ART partition issue in LibreRouter OS 1.5 → 2.0 upgrades.

**Problem:** LibreRouter OS 1.5 has `mtdparts=...64k(ART)` (uppercase) in U-Boot `boot_1` and `boot_2` parameters, which prevents the kernel from loading WiFi calibration data.

**Solution:** This self-extracting installer automatically fixes the case to `64k(art)` (lowercase) before upgrading.

## Files

- `files/usr/bin/librerouter-art-fix-installer.sh` - Main installer script
- `build-installer.sh` - Helper to build self-extracting installer
- `README-INSTALLER.md` - This documentation

## Building a Self-Extracting Installer

### Prerequisites

- LibreRouter sysupgrade firmware image (.bin)
- Updated safe-upgrade script from master branch
- This eupgrade package directory

### Download safe-upgrade

```bash
cd /path/to/lime-packages/packages/eupgrade
wget https://raw.githubusercontent.com/libremesh/lime-packages/refs/heads/master/packages/safe-upgrade/files/usr/sbin/safe-upgrade -O safe-upgrade-fixed.lua
```

### Build Process

```bash
cd /path/to/lime-packages/packages/eupgrade
./build-installer.sh /path/to/librerouter-v1-sysupgrade.bin
```

**Output:** Creates `librerouter-v1-sysupgrade-installer.sh`

This file contains three parts:
1. The installer script (shell code)
2. The safe-upgrade script (updated version with correct "art" template)
3. The firmware image (binary data)

## Generating eupgrade Metadata

After building the installer, generate JSON metadata for eupgrade:

```bash
./generate-metadata.sh librerouter-v1-sysupgrade-installer.sh
```

This creates:

- `librerouter-librerouter-v1.json` - Metadata file with version info and SHA256
- `librerouter-librerouter-v1.json.sig` - Signature file (mock by default)

**For production with custom URL:**

```bash
./generate-metadata.sh \
    librerouter-v1-sysupgrade-installer.sh \
    http://repo.librerouter.org/art-fix/releases/1.0
```

**With real cryptographic signature:**

```bash
SIGNING_KEY=/path/to/private.key \
    ./generate-metadata.sh librerouter-v1-sysupgrade-installer.sh
```

See [METADATA-GENERATION.md](METADATA-GENERATION.md) for detailed documentation on:

- Deployment workflow
- Server directory structure
- Cryptographic signature generation
- Troubleshooting

### Generated Metadata Format

The generated JSON follows eupgrade's expected structure:

```json
{
    "metadata-version": 1,
    "images": [
        {
            "name": "librerouter-v1-sysupgrade-installer.sh",
            "type": "installer",
            "download-urls": [
                "http://repo.librerouter.org/art-fix/releases/1.0/librerouter-v1-sysupgrade-installer.sh"
            ],
            "sha256": "abc123..."
        }
    ],
    "board": "librerouter,librerouter-v1",
    "version": "LibreRouterOs 1.5 r0+11434-e93615c947",
    "release-info-url": "https://foro.librerouter.org/art-fix-announcement"
}
```

## What the Installer Does

When executed (either manually or via eupgrade), it:

1. ✅ **Checks prerequisites** - Verifies fw_printenv, fw_setenv, lua are available
2. ✅ **Verifies board** - Ensures it's running on LibreRouter V1 (fails on other boards)
3. ✅ **Extracts and installs safe-upgrade** - Updates /usr/sbin/safe-upgrade with fixed version
4. ✅ **Re-bootstraps safe-upgrade** - Recreates boot_1 and boot_2 with correct "art" template
5. ✅ **Detects partitions** - Identifies current and next boot partition using /proc/mtd
6. ✅ **Fixes ART case** - Double-checks and corrects `boot_N` parameter if ART still uppercase
7. ✅ **Extracts firmware** - Extracts embedded .bin from end of script to /tmp
8. ✅ **Runs safe-upgrade** - Executes `safe-upgrade upgrade -n` with extracted image

## Status Files (eupgrade Integration)

The installer follows eupgrade conventions:

- **Status:** `/tmp/upgrade-installer-status`
  - `running` - Installer is executing
  - `success` - Upgrade initiated successfully
  - `failed` - An error occurred

- **Error:** `/tmp/upgrade-installer-error-mesage` (note: typo is intentional)
  - Contains error message if status is `failed`

- **Log:** `/tmp/upgrade-installer.log`
  - Detailed log output (via stderr redirect from eupgrade)

## Manual Testing

### Test on LibreRouter

```bash
# Upload installer to router
scp librerouter-v1-sysupgrade-installer.sh root@192.168.1.1:/tmp/

# SSH to router
ssh root@192.168.1.1

# Check current boot_2 parameter
fw_printenv boot_2

# Run installer (will upgrade and reboot!)
/tmp/librerouter-v1-sysupgrade-installer.sh 2>&1 | tee /tmp/upgrade-installer.log

# Monitor progress (from another terminal)
tail -f /tmp/upgrade-installer.log
```

### Test Dry Run (without actual upgrade)

To test without upgrading, modify the installer to skip `execute_upgrade()`:

```bash
# Comment out the execute_upgrade line in main()
sed -i 's/execute_upgrade/# execute_upgrade/' librerouter-v1-sysupgrade-installer.sh
```

This will test all steps except the actual safe-upgrade execution.

## Edge Cases Handled

### 1. ART Already in Lowercase
If `boot_N` already has `64k(art)`, the installer skips the fix and proceeds with upgrade.

### 2. safe-upgrade Not Bootstrapped
If `boot_N` doesn't exist in U-Boot environment (pre-bootstrap), the installer skips the fix with a warning. The subsequent safe-upgrade bootstrap/upgrade will create `boot_N` with correct case.

### 3. Wrong Board
If board is not LibreRouter V1, the installer exits with error before making any changes.

### 4. Insufficient Space
If /tmp has less than 10MB free, the installer exits before extracting firmware.

### 5. Corrupted Payload
If extracted firmware is less than 1MB, the installer exits before flashing.

## Troubleshooting

### "Required command not found"
- **Cause:** Missing fw_printenv, fw_setenv, or safe-upgrade
- **Solution:** Install safe-upgrade package

### "Unsupported board"
- **Cause:** Installer is running on non-LibreRouter device
- **Solution:** This installer is LibreRouter V1 specific

### "boot_N not found in U-Boot environment"
- **Status:** Warning (not an error)
- **Meaning:** safe-upgrade not yet bootstrapped
- **Action:** Installer continues, safe-upgrade will create boot_N correctly

### "Verification failed: uppercase ART still present"
- **Cause:** fw_setenv failed to apply the fix
- **Solution:** Check /etc/fw_env.config, try running fw_setenv manually

### "Could not find __PAYLOAD_BELOW__ marker"
- **Cause:** Installer script was modified or firmware wasn't concatenated
- **Solution:** Rebuild installer using build-installer.sh

## Security Considerations

- ✅ **Board verification** - Only runs on LibreRouter V1
- ✅ **Input validation** - Checks all prerequisites before making changes
- ✅ **Atomic updates** - Uses `fw_setenv -s -` for atomic U-Boot env updates
- ✅ **Verification** - Re-reads boot_N after modification to confirm
- ✅ **Size checks** - Validates extracted firmware size
- ✅ **Requires root** - fw_printenv/fw_setenv require root privileges

## Development

### Running Tests

```bash
# Test sed pattern
bash /tmp/test-art-sed.sh

# Test self-extraction
cd /tmp
./test-full-installer.sh
```

### Modifying the Installer

1. Edit `files/usr/bin/librerouter-art-fix-installer.sh`
2. Test changes
3. Rebuild installer with `./build-installer.sh`

## References

- **HackMD Documentation:** https://hackmd.io/Kknwo05QRu-R9cFLBIqMbg
- **safe-upgrade:** `/lime-packages/packages/safe-upgrade/files/usr/sbin/safe-upgrade`
- **eupgrade integration:** `/lime-packages/packages/ubus-lime-utils/files/usr/lib/lua/lime/upgrade.lua:134-144`
- **Issue tracker:** https://github.com/libremesh/lime-packages/issues

## License

GPL-3.0-or-later

---

**Created:** 2025-12-26
**Author:** AI-assisted development
**Maintainer:** LibreMesh Project
