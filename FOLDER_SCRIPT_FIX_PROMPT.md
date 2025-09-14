# PROMPT FOR FIXING PANZURA DEMO TOOLKIT FOLDER SCRIPT

## Problem Summary
The `create_folders.ps1` script is not properly setting folder ownership. All folders are getting `BUILTIN\Administrators` as owner instead of the intended AD groups like `PLAB\GG_Finance`.

## Root Cause Analysis
1. **AD Populator Issue**: The script was run without `-CreateAccessTiers` parameter, so it only created `GG_Finance` but not `GG_Finance_RO`, `GG_Finance_RW`, `GG_Finance_Owners` groups that the folder script expects.

2. **Set-OwnerAndGroup Function Issue**: The `Set-OwnerAndGroup` function in `set_privs.psm1` is not working properly - it's not actually changing ownership despite being called.

## Files to Fix
- `panzura_demo_toolkit_vNext/create_folders.ps1`
- `panzura_demo_toolkit_vNext/set_privs.psm1` (if needed)

## Expected Behavior
- Department root folders (e.g., `S:\Shared\Finance`) should be owned by `PLAB\GG_Finance`
- Subfolders should inherit proper ownership or have `BUILTIN\Administrators` (acceptable)
- IT folders should be owned by service accounts when available
- All folders should have proper NTFS permissions set

## Current Broken Behavior
- ALL folders show `BUILTIN\Administrators` as owner
- The `Set-OwnerAndGroup` function is called but ownership doesn't change
- Permissions are being set but ownership is wrong

## Test Environment
- Domain: `PLAB` (plab.local)
- AD Groups exist: `GG_Finance`, `GG_HR`, `GG_Engineering`, etc.
- Service accounts exist: `sql_service`, `backup_svc`, etc.
- Share: `S:\Shared`

## Required Fixes
1. **Fix the `Set-OwnerAndGroup` function** - it's not actually setting ownership
2. **Verify the `Resolve-DeptPrincipals` function** - ensure it returns correct group names
3. **Test ownership setting** - verify folders get proper AD group ownership
4. **Ensure error handling** - if AD groups don't exist, fall back gracefully

## Test Commands to Verify Fix
```powershell
# 1. Run AD populator with correct parameters
.\ad_populator.ps1 -BaseOUName DemoCorp -CreateAccessTiers -CreateAGDLP

# 2. Test folder creation
.\create_folders.ps1 -Departments @("Finance","HR") -Force

# 3. Verify ownership
Get-Acl "S:\Shared\Finance" | Select-Object Owner, Group
Get-Acl "S:\Shared\HR" | Select-Object Owner, Group

# 4. Spot check 25 random folders
Get-ChildItem "S:\Shared" -Recurse | Get-Random -Count 25 | ForEach-Object { 
    $acl = Get-Acl $_.FullName
    [PSCustomObject]@{
        Path = $_.FullName
        Owner = $acl.Owner
        Group = $acl.Group
    }
} | Format-Table -AutoSize
```

## Success Criteria
- Department root folders owned by `PLAB\GG_Finance`, `PLAB\GG_HR`, etc.
- NOT `BUILTIN\Administrators` on department roots
- Subfolders can be `BUILTIN\Administrators` (acceptable)
- IT folders owned by service accounts when available
- All folders have proper NTFS permissions

## Current Working Directory
`C:\Users\Administrator.PLAB\Documents\cursor\pan-demo-data\panzura_demo_toolkit_vNext`

## Additional Context
- The script was tested three times with different configurations
- All tests showed the same ownership issue
- The problem was identified as not following the documented AD populator parameters
- The `Set-OwnerAndGroup` function needs to be debugged and fixed
- This is blocking proper AD integration for the Panzura demo environment
