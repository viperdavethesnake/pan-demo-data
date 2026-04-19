# Pick-ServiceAccountForPath — pick a service account SAM whose PathPatterns
# match the given path. Null if none match. Weighted equal among matching.
function Pick-ServiceAccountForPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$Path,
        [System.Random]$Rng = $null
    )
    if (-not $Rng) { $Rng = [System.Random]::new() }
    $matches = @()
    $pathLower = $Path -replace '\\','/'
    foreach ($svc in $Config.Mess.ServiceAccounts) {
        foreach ($pat in $svc.PathPatterns) {
            if ($pathLower -like ($pat -replace '\\','/')) {
                $matches += $svc.Name
                break
            }
        }
    }
    if ($matches.Count -eq 0) { return $null }
    return $matches[$Rng.Next(0, $matches.Count)]
}

# Resolve-OwnerForFile — given the 5-way ownership mix + path + context,
# pick the owner principal (NTAccount form "DOMAIN\principal").
#
# When the path resolves to a non-dept folder (Department='General'),
# GG_<Department> doesn't exist — fall back to GG_AllEmployees for dept-group
# ownership, and draw user ownership from the full real-user pool.
function Resolve-OwnerForFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string]$Department,
        [Parameter(Mandatory)][hashtable]$ADCache,
        [System.Random]$Rng = $null
    )
    if (-not $Rng) { $Rng = [System.Random]::new() }

    $mix = $Config.Files.Ownership
    $roll = $Rng.NextDouble()
    $acc = 0.0
    $bucket = 'DeptGroup'
    foreach ($key in @('DeptGroup','User','ServiceAccount','OrphanSid','BuiltinAdmin')) {
        $acc += [double]$mix[$key]
        if ($roll -lt $acc) { $bucket = $key; break }
    }

    $domain = $ADCache.Domain
    $isKnownDept = $ADCache.ByDept.ContainsKey($Department)
    $deptGroupAccount = if ($isKnownDept) { "$domain\GG_$Department" } else { "$domain\GG_AllEmployees" }

    switch ($bucket) {
        'DeptGroup' {
            return @{ Bucket='DeptGroup'; Account=$deptGroupAccount }
        }
        'User' {
            $sams = if ($isKnownDept) { $ADCache.ByDept[$Department] } else { $ADCache.AllReal }
            if ($sams -and $sams.Count -gt 0) {
                $realOnly = $sams | Where-Object { $ADCache.Orphans -notcontains $_ }
                if ($realOnly -and $realOnly.Count -gt 0) {
                    $sam = $realOnly[$Rng.Next(0, $realOnly.Count)]
                    return @{ Bucket='User'; Account="$domain\$sam" }
                }
            }
            return @{ Bucket='DeptGroup'; Account=$deptGroupAccount }
        }
        'ServiceAccount' {
            $svc = Pick-ServiceAccountForPath -Config $Config -Path $FilePath -Rng $Rng
            if ($svc) { return @{ Bucket='ServiceAccount'; Account="$domain\$svc" } }
            return @{ Bucket='DeptGroup'; Account=$deptGroupAccount }
        }
        'OrphanSid' {
            if ($ADCache.Orphans.Count -gt 0) {
                $o = $ADCache.Orphans[$Rng.Next(0, $ADCache.Orphans.Count)]
                return @{ Bucket='OrphanSid'; Account="$domain\$o" }
            }
            return @{ Bucket='DeptGroup'; Account=$deptGroupAccount }
        }
        'BuiltinAdmin' {
            return @{ Bucket='BuiltinAdmin'; Account='BUILTIN\Administrators' }
        }
    }
    return @{ Bucket='DeptGroup'; Account=$deptGroupAccount }
}
