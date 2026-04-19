# Get-AclMessRoll — roll a weighted ACL pattern name from config.
function Get-AclMessRoll {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [System.Random]$Rng = $null
    )
    if (-not $Rng) { $Rng = [System.Random]::new() }
    (Get-WeightedChoiceFromPctArray -Records $Config.Mess.AclPatterns -Rng $Rng).Name
}

# Get-FileClassRoll — roll a file class from TimestampModel, biased by folder pattern.
# bias = dormancy override; we treat it as "P(Dormant or LegacyArchive)".
function Get-FileClassRoll {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$RelFolderPath,
        [System.Random]$Rng = $null
    )
    if (-not $Rng) { $Rng = [System.Random]::new() }
    $classes = $Config.TimestampModel.FileClasses
    $map = $Config.TimestampModel.DormancyByFolderPattern

    # Find dormancy bias
    $bias = $null
    foreach ($pat in $map.Keys) {
        if ($pat -eq 'default') { continue }
        if (Test-FolderPatternMatch -Pattern $pat -Path $RelFolderPath) { $bias = [double]$map[$pat]; break }
    }
    if ($null -eq $bias) { $bias = [double]$map['default'] }

    # Default Pct share of Dormant+LegacyArchive is 20 (15+5). If $bias differs,
    # scale these two and normalize the rest.
    $dormantBase = 0
    foreach ($c in $classes) {
        if ($c.Name -in @('Dormant','LegacyArchive')) { $dormantBase += [double]$c.Pct }
    }
    if ($dormantBase -le 0) {
        return (Get-WeightedChoiceFromPctArray -Records $classes -Rng $Rng)
    }
    $nonDormantBase = 100.0 - $dormantBase
    $targetDormant = $bias * 100.0
    $targetNonDormant = 100.0 - $targetDormant

    $scaled = foreach ($c in $classes) {
        $newPct = if ($c.Name -in @('Dormant','LegacyArchive')) {
            [double]$c.Pct * ($targetDormant / $dormantBase)
        } else {
            [double]$c.Pct * ($targetNonDormant / $nonDormantBase)
        }
        @{ Name = $c.Name; Pct = $newPct; WriteGapMin=$c.WriteGapMin; WriteGapMax=$c.WriteGapMax; AccessGapMin=$c.AccessGapMin; AccessGapMax=$c.AccessGapMax }
    }
    return (Get-WeightedChoiceFromPctArray -Records $scaled -Rng $Rng)
}
