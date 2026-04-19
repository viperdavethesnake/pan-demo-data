# Invoke-ParallelFileChunk — execute a pre-planned chunk of file work items
# via ForEach-Object -Parallel.
#
# Per-file invariant order (load-bearing; see spec §2):
#   1. Open → write magic → FSCTL_SET_SPARSE → seek/write(size-1)
#   2. SetAttributes
#   3. ADS (Zone.Identifier) — must be before timestamps
#   4. Set owner via minimal FileSecurity (skip Get-Acl; 53% faster)
#   5. Apply file-level ACL mess (explicit ACE / deny / detach) if requested
#   6. SetCreationTime / SetLastWriteTime / SetLastAccessTime — absolute last
#
# NOTE: Benchmark evidence shows ForEach-Object -Parallel is *not* faster
# than sequential on NTFS for this workload (kernel serialization on ACL
# ops + per-item runspace overhead). Kept for completeness; correctness
# is the priority here, not throughput.

function Invoke-ParallelFileChunk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Chunk,
        [Parameter(Mandatory)][int]$ThrottleLimit
    )
    if ($Chunk.Count -eq 0) {
        return [pscustomobject]@{ Created = 0; Errors = 0; Items = @() }
    }

    $results = $Chunk | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
        $item = $_
        try {
            # --- 1. Sparse file create ---
            $dir = [IO.Path]::GetDirectoryName($item.Path)
            if ($dir -and -not (Test-Path -LiteralPath $dir)) {
                [void][IO.Directory]::CreateDirectory($dir)
            }
            if (Test-Path -LiteralPath $item.Path) { [IO.File]::Delete($item.Path) }
            $fs = [IO.File]::Open($item.Path, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try {
                if ($item.Hdr -and $item.Hdr.Length -gt 0) {
                    $writeLen = [Math]::Min([long]$item.Hdr.Length, $item.Size)
                    $fs.Write($item.Hdr, 0, [int]$writeLen)
                }
                [PanzuraDemo.Native.Sparse]::SetSparse($fs.SafeFileHandle)
                if ($item.Size -gt 1) {
                    [void]$fs.Seek($item.Size - 1, [IO.SeekOrigin]::Begin)
                    $fs.WriteByte(0)
                }
            } finally { $fs.Close() }

            # --- 2. Attributes ---
            $normalAttr = [int][IO.FileAttributes]::Normal
            if ($item.Attrs -ne $normalAttr) {
                [IO.File]::SetAttributes($item.Path, [IO.FileAttributes]$item.Attrs)
            }

            # --- 3. ADS (before timestamps) ---
            if ($item.Ads) {
                try {
                    [IO.File]::WriteAllText("$($item.Path):Zone.Identifier", "[ZoneTransfer]`r`nZoneId=3`r`n")
                } catch {}
            }

            # --- 4. Owner via minimal FileSecurity ---
            try {
                $sec = New-Object System.Security.AccessControl.FileSecurity
                $sec.SetOwner([System.Security.Principal.NTAccount]::new($item.Owner))
                Set-Acl -LiteralPath $item.Path -AclObject $sec
            } catch {}

            # --- 5. File-level ACL mess ---
            if ($item.AclOp -eq 'AllowAce' -and $item.AclIdentity) {
                try {
                    $acl = Get-Acl -LiteralPath $item.Path
                    $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
                        $item.AclIdentity,
                        [System.Security.AccessControl.FileSystemRights]::Modify,
                        [System.Security.AccessControl.AccessControlType]::Allow)
                    $acl.AddAccessRule($rule)
                    Set-Acl -LiteralPath $item.Path -AclObject $acl
                } catch {}
            } elseif ($item.AclOp -eq 'DenyAce' -and $item.AclIdentity) {
                try {
                    $acl = Get-Acl -LiteralPath $item.Path
                    $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
                        $item.AclIdentity,
                        [System.Security.AccessControl.FileSystemRights]::Write,
                        [System.Security.AccessControl.AccessControlType]::Deny)
                    $acl.AddAccessRule($rule)
                    Set-Acl -LiteralPath $item.Path -AclObject $acl
                } catch {}
            } elseif ($item.AclOp -eq 'Detach') {
                try {
                    $acl = Get-Acl -LiteralPath $item.Path
                    $acl.SetAccessRuleProtection($true, $true)
                    Set-Acl -LiteralPath $item.Path -AclObject $acl
                } catch {}
            }

            # --- 6. Timestamps LAST ---
            [IO.File]::SetCreationTime($item.Path, $item.CT)
            [IO.File]::SetLastWriteTime($item.Path, $item.WT)
            [IO.File]::SetLastAccessTime($item.Path, $item.AT)

            [pscustomobject]@{
                Ok          = $true
                Path        = $item.Path
                Owner       = $item.Owner
                OwnerBucket = $item.OwnerBucket
                Size        = $item.Size
                ClassName   = $item.ClassName
                CT          = $item.CT
                WT          = $item.WT
                AT          = $item.AT
            }
        } catch {
            [pscustomobject]@{ Ok = $false; Err = $_.Exception.Message; Path = $item.Path }
        }
    }

    $ok  = @($results | Where-Object { $_.Ok })
    $err = @($results | Where-Object { -not $_.Ok })

    [pscustomobject]@{
        Created = $ok.Count
        Errors  = $err.Count
        Items   = $ok
    }
}
