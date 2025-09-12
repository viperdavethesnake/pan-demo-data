param(
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [string]$Owner,          # e.g. "PLAB\SomeUser" or "PLAB\Domain Admins"

    [string]$Group,          # optional: "PLAB\SomeGroup"

    [switch]$Recurse,        # apply to all child items
    [switch]$WhatIf
)

# --- Enable SeRestorePrivilege & SeTakeOwnershipPrivilege for this process ---
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

# Enable required privileges
Write-Host "Enabling SeRestorePrivilege and SeTakeOwnershipPrivilege..." -ForegroundColor Yellow
$restore = [Win32.AdvApi]::EnablePrivilege("SeRestorePrivilege")
$takeown = [Win32.AdvApi]::EnablePrivilege("SeTakeOwnershipPrivilege")

if ($restore -and $takeown) {
    Write-Host "✓ Privileges enabled successfully" -ForegroundColor Green
} else {
    Write-Host "⚠ Warning: Some privileges may not have been enabled" -ForegroundColor Yellow
}

# --- Helper to set owner/group on one item ---
function Set-OwnerGroup {
    param(
        [System.IO.FileSystemInfo]$Item,
        [string]$OwnerNT,
        [string]$GroupNT = $null,
        [switch]$WhatIf
    )

    $acl = Get-Acl -LiteralPath $Item.FullName

    # Owner
    $ownerAcct = New-Object System.Security.Principal.NTAccount($OwnerNT)
    $acl.SetOwner($ownerAcct)

    # Group (optional)
    if ($GroupNT) {
        $groupAcct = New-Object System.Security.Principal.NTAccount($GroupNT)
        $acl.SetGroup($groupAcct)
    }

    if ($WhatIf) {
        Write-Host "[WhatIf] Would set OWNER='$OwnerNT'$(if($GroupNT){" and GROUP='$GroupNT'"} ) on '$($Item.FullName)'"
    } else {
        Set-Acl -LiteralPath $Item.FullName -AclObject $acl
    }
}

# --- Collect targets ---
$targets = @()
if (Test-Path -LiteralPath $Path) {
    $base = Get-Item -LiteralPath $Path
    $targets += $base
    if ($Recurse) {
        $targets += Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
} else {
    throw "Path not found: $Path"
}

# --- Apply ---
$successCount = 0
$errorCount = 0

foreach ($t in $targets) {
    try {
        Set-OwnerGroup -Item $t -OwnerNT $Owner -GroupNT $Group -WhatIf:$WhatIf
        $successCount++
        if (-not $WhatIf) {
            Write-Host "✓ Set ownership on: $($t.FullName)" -ForegroundColor Green
        }
    }
    catch {
        Write-Warning "Failed on '$($t.FullName)': $($_.Exception.Message)"
        $errorCount++
    }
}

Write-Host ""
Write-Host "Done. Success: $successCount, Errors: $errorCount" -ForegroundColor Cyan
