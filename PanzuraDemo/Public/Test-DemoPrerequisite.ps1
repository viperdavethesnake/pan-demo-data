function Test-DemoPrerequisite {
<#
.SYNOPSIS
    Environment readiness check for PanzuraDemo.

.DESCRIPTION
    Validates that the host meets the requirements to run the pipeline:
    PowerShell 7+, elevated session, S: drive present and NTFS, sparse support,
    AD module available and domain reachable, share root writeable.

.PARAMETER Config
    Config hashtable from Import-DemoConfig. If omitted, loads default config.

.OUTPUTS
    [PSCustomObject] with a .Pass boolean and a .Checks array of per-check results.
#>
    [CmdletBinding()]
    param(
        [hashtable]$Config
    )
    if (-not $Config) { $Config = Import-DemoConfig }
    $checks = @()
    $add = { param($name, $ok, $detail) $script:_c = [pscustomobject]@{ Name=$name; Pass=[bool]$ok; Detail=$detail }; $checks += $script:_c }

    # PS version
    $psv = $PSVersionTable.PSVersion
    & $add 'PowerShell 7+' ($psv.Major -ge 7) "version=$psv"

    # Admin
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    & $add 'Elevated session' $isAdmin ''

    # S: drive + NTFS
    $root = $Config.Share.Root
    $drive = (Split-Path $root -Qualifier)
    $driveLetter = $drive.TrimEnd(':')
    $drivePresent = [bool](Get-PSDrive $driveLetter -ErrorAction SilentlyContinue)
    & $add "Drive $drive present" $drivePresent ''

    $fs = $null
    if ($drivePresent) {
        try { $fs = (Get-Volume -DriveLetter $driveLetter -ErrorAction Stop).FileSystem } catch {}
    }
    & $add "Drive $drive is NTFS" ($fs -eq 'NTFS') "fs=$fs"

    # Sparse test
    $sparseOk = $false
    $sparseErr = $null
    if ($drivePresent -and $fs -eq 'NTFS') {
        try {
            $probeDir = Join-Path $root '.probe'
            if (-not (Test-Path $probeDir)) { New-Item -ItemType Directory -Path $probeDir -Force | Out-Null }
            $probe = Join-Path $probeDir ("sparse_probe_{0}.bin" -f (Get-Random))
            $fsh = [IO.File]::Create($probe)
            try {
                [PanzuraDemo.Native.Sparse]::SetSparse($fsh.SafeFileHandle)
                $fsh.Seek(65536, [IO.SeekOrigin]::Begin) | Out-Null
                $fsh.WriteByte(0)
            } finally { $fsh.Close() }
            $sparseOk = [PanzuraDemo.Native.Sparse]::IsSparse($probe)
            Remove-Item $probe -Force -ErrorAction SilentlyContinue
        } catch {
            $sparseErr = $_.Exception.Message
        }
    }
    & $add "Sparse file support on $drive" $sparseOk ($sparseErr ? $sparseErr : '')

    # Write test
    $writable = $false
    if ($drivePresent) {
        try {
            $probe = Join-Path $root ".write_probe_{0}.tmp" -f (Get-Random)
            Set-Content -LiteralPath $probe -Value 'x' -ErrorAction Stop
            Remove-Item $probe -Force -ErrorAction SilentlyContinue
            $writable = $true
        } catch {}
    }
    & $add "$root is writable" $writable ''

    # AD module
    $adOk = $false; $domain = $null
    try {
        Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop
        $d = Get-ADDomain -ErrorAction Stop
        $adOk = $true
        $domain = "$($d.DNSRoot) (NetBIOS=$($d.NetBIOSName))"
    } catch {
        $domain = $_.Exception.Message
    }
    & $add 'Active Directory reachable' $adOk "domain=$domain"

    # SmbShare
    $smbOk = $false
    try { Import-Module SmbShare -SkipEditionCheck -ErrorAction Stop; $smbOk = $true } catch {}
    & $add 'SmbShare module available' $smbOk ''

    $allOk = -not ($checks | Where-Object { -not $_.Pass })
    [pscustomobject]@{
        Pass   = [bool]$allOk
        Checks = $checks
    }
}
