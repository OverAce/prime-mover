# PrimeMover ServerPilot to GridPane Migration Improvements

## Overview

This document outlines the improvements made to ensure smooth and reliable ServerPilot to GridPane migrations.

## Critical Issues Fixed

### 1. GridPane API Token Validation
**Problem:** The script used `$gridpanetoken` without verifying it exists or is valid, causing silent failures.

**Solution:**
- Added `ValidateGridPaneToken()` function that:
  - Checks if token is set
  - Tests token with GridPane API
  - Prompts user if missing
  - Saves to `~/.bash_profile` for future use

**Location:** `primemover.sh:60-93`

### 2. Disk Space Verification
**Problem:** Creating tar.gz archives could fill the disk, causing failures mid-migration.

**Solution:**
- Added `CheckDiskSpace()` function that:
  - Checks available disk space before packaging
  - Warns if less than 10GB available
  - Allows user to continue or abort
  - Prevents disk full errors

**Location:** `primemover.sh:95-122`

### 3. Bash Profile Sourcing
**Problem:** Script sourced `~/.bash_profile` without checking if it exists, causing errors.

**Solution:**
- Added conditional check before sourcing
- Only sources if file exists
- Prevents startup errors

**Location:** `primemover.sh:14-17`

### 4. Comprehensive Logging
**Problem:** No detailed logs for troubleshooting failed migrations.

**Solution:**
- Added timestamped logging to `/var/tmp/primemover/migration-*.log`
- `LogMessage()` function logs all critical operations
- Helps diagnose issues post-migration

**Location:** `primemover.sh:53-58`

### 5. Improved Error Handling
**Problem:** Inconsistent error tracking, no detailed error messages.

**Solution:**
- Added `HandleError()` function with:
  - Detailed error messages
  - Site identification
  - Log file references
  - Proper error flag setting

**Location:** `primemover.sh:124-147`

### 6. Polling Instead of Fixed Sleeps
**Problem:** Hard-coded `sleep` statements didn't account for varying site provision times.

**Solution:**
- Added `WaitForRemoteSite()` function that:
  - Polls every 5 seconds for site readiness
  - Shows progress every 30 seconds
  - Configurable timeout (default 5 minutes)
  - Prevents timeouts on large sites

**Location:** `primemover.sh:149-174`

### 7. Post-Migration Verification
**Problem:** No verification that migrated sites work correctly.

**Solution:**
- Added `VerifySiteMigration()` function that:
  - Verifies WordPress is installed
  - Checks database connectivity
  - Confirms site URL
  - Reports success/failure clearly

**Location:** `primemover.sh:176-210`

### 8. Enhanced Database Export
**Problem:** Limited error handling, no validation of exported database.

**Solution:**
- Improved `DBExport()` with:
  - Exit code checking
  - Better fallback to mysqldump
  - Validation of exported file size
  - Clear error messages
  - Credential extraction validation

**Location:** `primemover.sh:1334-1386`

### 9. Robust Site Packaging
**Problem:** No verification that tar.gz creation succeeded.

**Solution:**
- Enhanced `PackageSite()` with:
  - Disk space check before starting
  - Exit code validation
  - Archive size verification
  - Progress reporting
  - Better cleanup on errors

**Location:** `primemover.sh:1440-1502` (ServerPilot section)

### 10. Verified Migration Transfer
**Problem:** No validation that file transfers and restoration succeeded.

**Solution:**
- Improved `DoMigrate()` with:
  - SCP exit code checking
  - Restoration status verification
  - Post-migration verification call
  - Clear success/failure reporting
  - Detailed progress messages

**Location:** `primemover.sh:1723-1794`

### 11. Pre-Flight Checks
**Problem:** No validation before starting migration batch.

**Solution:**
- Enhanced `SPtoGP()` and `RCtoGP()` with:
  - API token validation
  - Disk space checks
  - SSH setup verification
  - Clear migration summary at completion

**Locations:**
- `primemover.sh:2005-2046` (SPtoGP)
- `primemover.sh:2048-2089` (RCtoGP)

### 12. Improved Remote Site Building
**Problem:** Fixed 3-second wait insufficient for large sites, no error checking on API calls.

**Solution:**
- Enhanced `MakeSiteonRemote()` with:
  - GridPane API response validation
  - Polling for site readiness
  - Better logging
  - Clearer error messages

**Location:** `primemover.sh:1243-1332`

## Benefits

### Reliability
- Validates all prerequisites before starting
- Checks exit codes for all operations
- Prevents silent failures

### Transparency
- Comprehensive logging for troubleshooting
- Clear progress indicators
- Detailed success/failure reporting

### Resilience
- Handles errors gracefully
- Provides helpful error messages
- Prevents disk full scenarios

### User Experience
- Better progress feedback
- Clear instructions when issues occur
- Automatic recovery where possible

## Migration Success Checklist

Before running ServerPilot to GridPane migration:

1. ✓ GridPane API token validated
2. ✓ Sufficient disk space (15GB+ recommended)
3. ✓ SSH connectivity established
4. ✓ WP-CLI installed and functional
5. ✓ Source sites are valid WordPress installs

During migration:

1. ✓ Database export verified
2. ✓ Site archive created and validated
3. ✓ Remote site provisioned
4. ✓ Files transferred successfully
5. ✓ Site restored on remote server
6. ✓ WordPress and database verified

After migration:

1. ✓ Site URL confirmed
2. ✓ Database accessible
3. ✓ WordPress responding
4. ✓ Log file available for review

## Testing Recommendations

### Small Site Test (< 1GB)
```bash
primemover SP2GP
# Follow prompts, verify single small site migrates correctly
```

### Medium Site Test (1-5GB)
```bash
primemover SP2GP
# Test with a typical production site
# Verify progress indicators work
# Confirm verification passes
```

### Large Site Test (> 5GB)
```bash
primemover SP2GP
# Test with large site to verify:
# - Disk space warnings work
# - Polling handles long provision times
# - Transfer completes successfully
```

### Error Recovery Test
```bash
# Intentionally break token, verify error handling:
export gridpanetoken="invalid"
primemover SP2GP
# Should catch invalid token early
```

## Log File Locations

- Migration logs: `/var/tmp/primemover/migration-YYYYMMDD-HHMMSS.log`
- Temporary files: `/var/tmp/primemover/`

## Known Limitations

1. Still requires root access on both servers
2. GridPane-specific restoration commands (gprestore)
3. Dropbox URLs for remote script download (legacy issue)
4. No rollback mechanism if migration fails

## Future Enhancements

1. Add rollback/undo functionality
2. Support resuming failed migrations
3. Parallel site migrations
4. Email notifications on completion
5. Web-based dashboard for monitoring
6. Bandwidth throttling for transfers
7. Incremental/differential migrations

## Version History

- **v1.1** (2025-11-13): Added comprehensive improvements for production readiness
  - API token validation
  - Disk space checking
  - Post-migration verification
  - Comprehensive logging
  - Better error handling
  - Polling instead of fixed sleeps

- **v1.0** (2018): Initial alpha release

## Support

For issues or questions:
- Email: patrick at gridpane dot com
- Check logs: `/var/tmp/primemover/migration-*.log`
- GitHub Issues: https://github.com/gridpane/prime-mover

## License

Copyright 2018 - K. Patrick Gallagher
