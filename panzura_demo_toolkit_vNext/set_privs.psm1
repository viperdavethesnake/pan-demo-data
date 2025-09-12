# set-privs.psm1 (self-healing)
# Enables SeRestore/SeTakeOwnership and provides helpers to set Owner/Group and NTFS ACLs.

# --- C# source for the type ---
$__priv_src = @'
using System;
using System.Runtime.InteropServices;
namespace Win32 {
  public static class AdvApi {
    [StructLayout(LayoutKind.Sequential)] public struct LUID { public uint LowPart; public int HighPart; }
    [StructLayout(LayoutKind.Sequential)] public struct LUID_AND_ATTRIBUTES { public LUID Luid; public UInt32 Attributes; }
    [StructLayout(LayoutKind.Sequential)] public struct TOKEN_PRIVILEGES { public UInt32 PrivilegeCount; public LUID_AND_ATTRIBUTES Privileges; }
    public const UInt32 TOKEN_ADJUST_PRIVILEGES = 0x20;
    public const UInt32 TOKEN_QUERY = 0x0008;
    public const UInt32 SE_PRIVILEGE_ENABLED = 0x00000002;
    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool OpenProcessToken(IntPtr ProcessHandle, UInt32 DesiredAccess, out IntPtr TokenHandle);
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out LUID lpLuid);
    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges,
        ref TOKEN_PRIVILEGES NewState, UInt32 BufferLength, IntPtr PreviousState, IntPtr ReturnLength);
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
}
'@

function Ensure-AdvApiType {
  if (-not ("Win32.AdvApi" -as [type])) {
    try {
      # Try to prevent notepad from opening by using a different compilation approach
      # Use a temporary directory that won't trigger file associations
      $tempDir = Join-Path $env:TEMP "PowerShell_AddType_$(Get-Random)"
      New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
      try {
        Add-Type -TypeDefinition $__priv_src -Language CSharp -ErrorAction Stop
      } finally {
        # Clean up the temporary directory
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
      }
    } catch {
      Write-Warning "Failed to compile C# type: $($_.Exception.Message)"
      throw
    }
  }
}

function Enable-Privilege {
  param([Parameter(Mandatory)][ValidateSet('SeRestorePrivilege','SeTakeOwnershipPrivilege')] [string]$Name)
  Ensure-AdvApiType
  [void][Win32.AdvApi]::EnablePrivilege($Name) | Out-Null
}

function Set-OwnerAndGroup {
  [CmdletBinding(SupportsShouldProcess=$true)]
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Owner,
    [string]$Group,
    [switch]$Recurse
  )
  Enable-Privilege -Name SeRestorePrivilege
  Enable-Privilege -Name SeTakeOwnershipPrivilege

  $targets = @()
  if (Test-Path -LiteralPath $Path) {
    $item = Get-Item -LiteralPath $Path -Force
    $targets += $item
    if ($Recurse -and $item.PSIsContainer) {
      $targets += Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
  } else { throw "Path not found: $Path" }

  foreach ($t in $targets) {
    try {
      $acl = Get-Acl -LiteralPath $t.FullName
      $ownerAcct = New-Object System.Security.Principal.NTAccount($Owner)
      $acl.SetOwner($ownerAcct)
      if ($Group) {
        $groupAcct = New-Object System.Security.Principal.NTAccount($Group)
        $acl.SetGroup($groupAcct)
      }
      if ($PSCmdlet.ShouldProcess($t.FullName,"Set Owner/Group")) {
        Set-Acl -LiteralPath $t.FullName -AclObject $acl
      }
    } catch {
      Write-Warning "Failed to set owner/group on '$($t.FullName)': $($_.Exception.Message)"
    }
  }
}

function Grant-FsAccess {
  [CmdletBinding(SupportsShouldProcess=$true)]
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Identity,
    [Parameter(Mandatory)][System.Security.AccessControl.FileSystemRights]$Rights,
    [ValidateSet('Allow','Deny')][string]$Type = 'Allow',
    [switch]$InheritToChildren,
    [switch]$ThisFolderOnly,
    [switch]$ClearExisting,
    [switch]$BreakInheritance,
    [switch]$CopyInheritance
  )
  $acl = Get-Acl -LiteralPath $Path

  if ($BreakInheritance) { $acl.SetAccessRuleProtection($true, $CopyInheritance) }
  if ($ClearExisting) { $acl.Access | Where-Object { -not $_.IsInherited } | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null } }

  $inheritFlags = [System.Security.AccessControl.InheritanceFlags]::None
  $propFlags = [System.Security.AccessControl.PropagationFlags]::None
  if ($InheritToChildren -and -not $ThisFolderOnly) {
    $inheritFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
  } elseif (-not $ThisFolderOnly) {
    $inheritFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
  }
  $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($Identity, $Rights, $inheritFlags, $propFlags, [System.Security.AccessControl.AccessControlType]::$Type)

  if ($PSCmdlet.ShouldProcess($Path,"Grant $Type $Rights to $Identity")) {
    $acl.AddAccessRule($rule) | Out-Null
    Set-Acl -LiteralPath $Path -AclObject $acl
  }
}

Export-ModuleMember -Function Enable-Privilege, Set-OwnerAndGroup, Grant-FsAccess
