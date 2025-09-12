# create-folders-sequential.ps1
# --- Sequential Folder Creator with 100% Domain User Ownership ---
# Removes parallel processing to ensure reliable ownership setting

param(
    [string]$RootPath = "S:\Shared",
    [switch]$WhatIf
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "SEQUENTIAL FOLDER CREATOR" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Root Path: $RootPath"
Write-Host "WhatIf Mode: $WhatIf"
Write-Host ""

# === ENABLE OWNERSHIP PRIVILEGES ===
Write-Host "Enabling ownership privileges..." -ForegroundColor Yellow

Add-Type -Namespace Win32 -Name AdvApi -MemberDefinition @"
using System;
using System.Runtime.InteropServices;

public class TokenTools {
  [DllImport("advapi32.dll", SetLastError=true)]
  public static extern bool OpenProcessToken(IntPtr ProcessHandle, UInt32 DesiredAccess, out IntPtr TokenHandle);

  [DllImport("advapi32.dll", SetLastError=true)]
  public static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out LUID lpLuid);

  [DllImport("advapi32.dll", SetLastError=true)]
  public static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges,
      ref TOKEN_PRIVILEGES NewState, UInt32 BufferLength, IntPtr PreviousState, IntPtr ReturnLength);

  [StructLayout(LayoutKind.Sequential)]
  public struct LUID { public uint LowPart; public int HighPart; }

  [StructLayout(LayoutKind.Sequential)]
  public struct LUID_AND_ATTRIBUTES {
    public LUID Luid;
    public UInt32 Attributes;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct TOKEN_PRIVILEGES {
    public UInt32 PrivilegeCount;
    public LUID_AND_ATTRIBUTES Privileges;
  }

  public const UInt32 TOKEN_ADJUST_PRIVILEGES = 0x20;
  public const UInt32 TOKEN_QUERY = 0x0008;
  public const UInt32 SE_PRIVILEGE_ENABLED = 0x00000002;

  public static bool EnablePrivilege(string name) {
    IntPtr hTok;
    if (!OpenProcessToken(System.Diagnostics.Process.GetCurrentProcess().Handle, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out hTok))
      return false;

    LUID luid;
    if (!LookupPrivilegeValue(null, name, out luid))
      return false;

    TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
    tp.PrivilegeCount = 1;
    tp.Privileges = new LUID_AND_ATTRIBUTES();
    tp.Privileges.Luid = luid;
    tp.Privileges.Attributes = SE_PRIVILEGE_ENABLED;

    return AdjustTokenPrivileges(hTok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
  }
}
"@

# Enable required privileges for ownership changes
$restore = [Win32.AdvApi]::EnablePrivilege("SeRestorePrivilege")
$takeown = [Win32.AdvApi]::EnablePrivilege("SeTakeOwnershipPrivilege")

if ($restore -and $takeown) {
    Write-Host "✓ Privileges enabled successfully" -ForegroundColor Green
} else {
    Write-Host "⚠ Warning: Some privileges may not have been enabled" -ForegroundColor Yellow
    Write-Host "  SeRestorePrivilege: $restore" -ForegroundColor Gray
    Write-Host "  SeTakeOwnershipPrivilege: $takeown" -ForegroundColor Gray
}
Write-Host ""

# === FUNCTIONS ===

function Get-ExistingDomainGroups {
    Write-Host "Retrieving existing domain groups..." -ForegroundColor Yellow
    try {
        $groups = Get-ADGroup -Filter * -SearchBase "CN=Users,DC=plab,DC=local" | Where-Object {
            $_.Name -notlike "*$*" -and  # Exclude computer accounts
            $_.Name -ne "Domain Users" -and
            $_.Name -ne "Domain Admins" -and
            $_.Name -ne "Domain Guests" -and
            $_.Name -ne "Panzura Admins" -and  # Exclude Symphony admin group
            $_.Name -notlike "*Admin*" -and     # Exclude other admin groups
            $_.Name -notlike "*Enterprise*" -and # Exclude Enterprise groups
            $_.Name -notlike "*Schema*" -and    # Exclude Schema groups
            $_.Name -notlike "*Key Admin*" -and # Exclude Key Admin groups
            $_.Name -notlike "*Domain Controller*" -and # Exclude DC groups
            $_.Name -notlike "*RODC*" -and      # Exclude RODC groups
            $_.Name -notlike "*Group Policy*" -and # Exclude GP groups
            $_.Name -notlike "*RAS and IAS*" -and  # Exclude RAS/IAS groups
            $_.Name -notlike "*Cert Publisher*" -and # Exclude Certificate groups
            $_.Name -notlike "*DnsAdmin*" -and   # Exclude DNS admin groups
            $_.Name -notlike "*DnsUpdateProxy*"  # Exclude DNS proxy groups
        }
        Write-Host "  Found $($groups.Count) domain groups" -ForegroundColor Green
        return $groups.Name
    } catch {
        Write-Host "  ✗ Failed to get domain groups: $_" -ForegroundColor Red
        return @()
    }
}

function Get-RandomDomainUsers {
    Write-Host "Retrieving domain users..." -ForegroundColor Yellow
    try {
        $users = Get-ADUser -Filter * -SearchBase "CN=Users,DC=plab,DC=local" | Where-Object {
            $_.SamAccountName -like "*.*" -and  # firstname.lastname pattern
            $_.SamAccountName -notlike "*$" -and  # Exclude computer accounts
            $_.SamAccountName -ne "krbtgt" -and
            $_.SamAccountName -ne "Guest" -and
            $_.SamAccountName -ne "Administrator" -and
            $_.SamAccountName -notlike "*_svc" -and  # Exclude service accounts
            $_.SamAccountName -notlike "*_service"
            # Remove Enabled check since it may be null for newly created accounts
        }
        Write-Host "  Found $($users.Count) domain users" -ForegroundColor Green
        return $users
    } catch {
        Write-Host "  ✗ Failed to get domain users: $_" -ForegroundColor Red
        return @()
    }
}

function Set-DomainOwnership {
    param([string]$Path, [string]$Owner)
    
    if ($WhatIf) {
        Write-Host "  WOULD SET owner of $Path to $Owner" -ForegroundColor Cyan
        return $true
    }
    
    try {
        # Use the proper privilege-enabled ACL method
        $acl = Get-Acl -LiteralPath $Path
        $ownerAcct = New-Object System.Security.Principal.NTAccount($Owner)
        $acl.SetOwner($ownerAcct)
        Set-Acl -LiteralPath $Path -AclObject $acl
        return $true
        
    } catch {
        Write-Host "  ✗ FAILED to set ownership to $Owner on ${Path}: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Set-FolderPermissions {
    param([string]$FolderPath, [array]$AvailableGroups)
    
    # Select 2-6 random groups for this folder
    $numGroups = Get-Random -Minimum 2 -Maximum 7
    $selectedGroups = $AvailableGroups | Get-Random -Count $numGroups
    
    if ($WhatIf) {
        Write-Host "  WOULD GRANT permissions to: $($selectedGroups -join ', ')" -ForegroundColor Cyan
        return $true
    }
    
    try {
        foreach ($group in $selectedGroups) {
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("PLAB\$group", "Modify", "ContainerInherit, ObjectInherit", "None", "Allow")
            $acl = Get-Acl $FolderPath
            $acl.SetAccessRule($rule)
            Set-Acl $FolderPath $acl
        }
        return $true
    } catch {
        Write-Host "  ✗ Failed to set permissions on $FolderPath" -ForegroundColor Red
        return $false
    }
}

# === MAIN EXECUTION ===

# Validate environment
Write-Host "Validating environment..." -ForegroundColor Yellow
if (-not (Test-Path $RootPath)) {
    Write-Host "✗ Root path does not exist: $RootPath" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Root path exists: $RootPath" -ForegroundColor Green

# Get domain groups and users
$domainGroups = Get-ExistingDomainGroups
if ($domainGroups.Count -eq 0) {
    Write-Host "✗ No domain groups found" -ForegroundColor Red
    exit 1
}

$domainUsers = Get-RandomDomainUsers
if ($domainUsers.Count -eq 0) {
    Write-Host "✗ No domain users found" -ForegroundColor Red
    exit 1
}

# Generate folder structure
Write-Host "Generating folder structure..." -ForegroundColor Yellow

$departments = @("Accounting", "Engineering", "Finance", "HR", "IT", "Legal", "Marketing", "Sales", "Support", "PreSales")
$years = @(2005..2025)
$subFolders = @("Backup", "Temp", "Archive", "Projects", "Personal", "Shared", "Old", "Review", "ToSort", "Junk", "Lost+Found", "Misc", "Copy of", "Staff", "General", "Documentation", "TestData", "Legacy", "AllHands", "TeamDrives", "OldFiles", "Recovered", "Hold", "Random", "Unsorted", "!_archive", "zzz_Archive", "!DO_NOT_USE")

$folders = @()

# Department folders
foreach ($dept in $departments) {
    foreach ($year in ($years | Get-Random -Count 4)) {
        $basePath = "$dept\$(Get-Random @('Cases','Docs','Reports','Files','Data','Projects'))\$year"
        $folders += $basePath
        
        # Add subfolders
        for ($i = 0; $i -lt (Get-Random -Minimum 1 -Maximum 4); $i++) {
            $subPath = $basePath + "\" + ($subFolders | Get-Random)
            $folders += $subPath
            
            # Sometimes add deeper folders
            if ((Get-Random -Maximum 100) -lt 30) {
                $deepPath = $subPath + "\" + ($subFolders | Get-Random)
                $folders += $deepPath
                
                # Staff subfolders
                if ($deepPath -notlike "*Staff*" -and (Get-Random -Maximum 100) -lt 40) {
                    $folders += $deepPath + "\Staff"
                }
            }
        }
    }
}

# Add some general folders
$folders += @("General", "Shared", "Temp", "OldFiles", "Projects", "TeamDrives", "TestData", "ToSort", "zzz_Archive", "!DO_NOT_USE")

# Add user folders
for ($i = 1; $i -le 30; $i++) {
    $folders += "!DO_NOT_USE\User$i"
    $folders += "Temp\User$(Get-Random -Minimum 1 -Maximum 210)"
}

# Add cross-department project folders
for ($i = 1; $i -le 20; $i++) {
    $dept1 = $departments | Get-Random
    $dept2 = $departments | Get-Random
    $projNum = Get-Random -Minimum 1 -Maximum 2000
    $folders += "Projects\$dept1-$dept2-Project_$projNum"
    if ((Get-Random -Maximum 100) -lt 50) {
        $folders += "Projects\$dept1-$dept2-Project_$projNum\zzz_Archive"
    }
}

# Remove duplicates and sort
$folders = $folders | Select-Object -Unique | Sort-Object
Write-Host "✓ Generated $($folders.Count) unique folder paths" -ForegroundColor Green

# Create folders sequentially with ownership
Write-Host "`nCreating folders sequentially with domain user ownership..." -ForegroundColor Yellow
$successCount = 0
$ownershipSuccessCount = 0
$startTime = Get-Date

for ($i = 0; $i -lt $folders.Count; $i++) {
    $folder = $folders[$i]
    $fullPath = Join-Path $RootPath $folder
    $randomUser = ($domainUsers | Get-Random).SamAccountName
    $owner = "PLAB\$randomUser"
    
    # Progress reporting
    if (($i + 1) % 100 -eq 0 -or ($i + 1) -eq $folders.Count) {
        $elapsed = (Get-Date) - $startTime
        $rate = ($i + 1) / $elapsed.TotalSeconds
        $eta = [TimeSpan]::FromSeconds(($folders.Count - $i - 1) / $rate)
        Write-Host "  Progress: $($i + 1)/$($folders.Count) folders | Rate: $([math]::Round($rate, 1))/sec | ETA: $($eta.ToString('hh\:mm\:ss'))" -ForegroundColor Green
    }
    
    try {
        if ($WhatIf) {
            Write-Host "WOULD CREATE: $fullPath (Owner: $owner)" -ForegroundColor Cyan
            $successCount++
            $ownershipSuccessCount++
        } else {
            # Create folder
            $null = New-Item -Path $fullPath -ItemType Directory -Force -ErrorAction Stop
            $successCount++
            
            # Set ownership
            if (Set-DomainOwnership -Path $fullPath -Owner $owner) {
                $ownershipSuccessCount++
            }
            
            # Set permissions
            Set-FolderPermissions -FolderPath $fullPath -AvailableGroups $domainGroups | Out-Null
        }
    } catch {
        Write-Host "  ✗ Failed to create $fullPath : $($_.Exception.Message)" -ForegroundColor Red
    }
}

$totalTime = (Get-Date) - $startTime

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "SEQUENTIAL FOLDER CREATION COMPLETE" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Folders processed: $($folders.Count)"
Write-Host "Folders created: $successCount"
Write-Host "Ownership successes: $ownershipSuccessCount"
Write-Host "Ownership success rate: $([math]::Round(($ownershipSuccessCount / $successCount) * 100, 1))%"
Write-Host "Total time: $($totalTime.ToString('hh\:mm\:ss'))"
Write-Host "Average rate: $([math]::Round($successCount / $totalTime.TotalSeconds, 1)) folders/second"
Write-Host "Domain groups available: $($domainGroups.Count)"
Write-Host "Domain users for ownership: $($domainUsers.Count)"
Write-Host ""

if ($WhatIf) {
    Write-Host "WhatIf mode completed - no actual changes made" -ForegroundColor Yellow
} else {
    if ($ownershipSuccessCount -eq $successCount) {
        Write-Host "✅ SUCCESS: 100% domain user ownership achieved!" -ForegroundColor Green
    } else {
        Write-Host "⚠️ WARNING: Only $([math]::Round(($ownershipSuccessCount / $successCount) * 100, 1))% ownership success" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "✓ Enterprise file server environment created!" -ForegroundColor Green
    Write-Host "✓ Each folder has 2-6 random domain groups with Modify permissions" -ForegroundColor Green
    Write-Host "✓ Folders owned by random domain users" -ForegroundColor Green
    Write-Host ""
    Write-Host "Ready for Symphony scanning!" -ForegroundColor Cyan
}
