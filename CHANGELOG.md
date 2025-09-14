# Changelog

## [1.1.0] - 2025-01-14

### Major Fixes

- **Ownership assignment fix**: Resolved critical issue where files were retaining default BUILTIN\Administrators ownership instead of proper AD-based ownership
- **100% ownership coverage**: All files now have realistic AD-based ownership (75% group-owned, 25% user-owned)
- **Production validation**: Successfully updated 15,303+ files with proper ownership from AD groups and users

### Bug Fixes

- Fixed silent failure in Set-OwnerAndGroupFromModule function that was preventing ownership changes
- Fixed missing -Confirm:$false parameter in ownership assignment calls
- Fixed AD group lookup failures that were causing fallback to default ownership
- Removed verbose diagnostic messages that were cluttering output during file creation

### New Features

- Added comprehensive ownership verification commands to RUNBOOK.txt
- Enhanced error handling in ownership assignment with proper verbose logging
- Improved AD user cache building for more reliable ownership assignment

### Documentation

- Updated README.md to reflect 100% ownership coverage achievement
- Updated RUNBOOK.txt with ownership verification commands
- Updated project README.md with ownership fix details
- Updated version numbers across all documentation

## [1.0.0] - 2025-01-27

### Major Enhancements

- **Enhanced folder structure**: Added 185+ folder types including year-based organization (2020-2025), project-specific directories, cross-department collaboration folders, duplicate structures, and naming convention chaos
- **Perfect timestamp realism**: Resolved all timestamp bugs - files and folders now have realistic historical timestamps with no current date contamination
- **Production validation**: Successfully tested with 4,961+ files across all scenarios (LegacyMess, RecentSkew, YearSpread, Custom ranges, No AD mode)
- **Sparse file excellence**: 100% sparse file creation verified across 50+ sample files for optimal Panzura Symphony testing
- **Smart file distribution**: Files properly distributed across all folder types with correct ownership mapping

### Bug Fixes

- Fixed timestamp bug in Apply-Timestamps function that was overriding generated dates with current offsets
- Fixed file distribution bug where MaxFiles parameter concentrated files in first folders only
- Fixed ownership mapping for enhanced folder types (cross-department and naming chaos folders)
- Fixed timestamp order issues where Set-RandomAttributes, Set-OwnerAndGroup, and Add-ADS were updating LastWriteTime after timestamps were set
- Fixed folder timestamp inconsistencies by adding Set-RealisticFolderTimestamps calls to all folder creation points
- Fixed future date issues in folder timestamps by capping offsets with Math.Min

### New Features

- Added clean_shared.ps1 utility for complete S:\Shared cleanup
- Enhanced create_folders.ps1 with realistic enterprise folder structure
- Added comprehensive parameter documentation to README.md
- Added validation results and production readiness confirmation

### Documentation

- Updated README.md with production-ready features and validation results
- Added comprehensive parameter examples and usage scenarios
- Updated troubleshooting section with resolved issues
- Added sparse file verification instructions

## [0.9.0] - Previous

- Add project-level README and onboarding docs (CONTRIBUTING, DEVELOPMENT, TROUBLESHOOTING).
- Rename versioned scripts to stable names; update references.
- Fix timestamp generation null errors; harden Get-RandomDate and Apply-Timestamps.
- Improve AD populator summary formatting and folder defaults (include Marketing).
- Normalize share ACLs end-state; cleanup script and output.
- Add TODO backlog (Messy mode, config, reporting, orchestration).
