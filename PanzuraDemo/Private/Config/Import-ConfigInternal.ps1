# Merge-DemoConfigInternal — deep-merge overlay hashtable into base hashtable.
# Merge rules:
#   - Hashtables deep-merge (overlay keys win; recursive)
#   - Arrays are REPLACED wholesale by overlay (not concatenated)
#   - Scalars are replaced by overlay
#   - $null in overlay does not overwrite (skips the key)

function Merge-DemoConfigInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Base,
        [Parameter(Mandatory)][hashtable]$Overlay
    )
    $result = @{}
    foreach ($k in $Base.Keys) { $result[$k] = $Base[$k] }
    foreach ($k in $Overlay.Keys) {
        $ov = $Overlay[$k]
        if ($null -eq $ov) { continue }
        if ($result.ContainsKey($k) -and ($result[$k] -is [hashtable]) -and ($ov -is [hashtable])) {
            $result[$k] = Merge-DemoConfigInternal -Base $result[$k] -Overlay $ov
        } else {
            $result[$k] = $ov
        }
    }
    return $result
}

# Test-DemoConfigInternal — schema validation. Throws on violations.
function Test-DemoConfigInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Config)

    $required = @('Metadata','Share','AD','Departments','ExtensionProperties','FileHeaders',
                  'NameTemplates','DataPools','FolderTree','Files','TimestampModel','Mess',
                  'Parallel','Scenarios')
    foreach ($r in $required) {
        if (-not $Config.ContainsKey($r)) { throw "Config missing required key '$r'." }
    }
    if (-not $Config.Departments -or $Config.Departments.Count -lt 1) {
        throw "Config.Departments must have at least one dept."
    }
    foreach ($d in $Config.Departments) {
        foreach ($dk in @('Name','SamPrefix','UsersPerDept','SubFolders','Extensions')) {
            if (-not $d.ContainsKey($dk)) { throw "Department '$($d.Name)' missing '$dk'." }
        }
    }
    # Ownership mix must sum to ~1.0
    $sum = 0.0
    foreach ($v in $Config.Files.Ownership.Values) { $sum += [double]$v }
    if ([math]::Abs($sum - 1.0) -gt 0.01) {
        throw "Files.Ownership must sum to 1.0 (currently $sum)."
    }
    # AclPatterns pct must sum to ~100
    $sum = 0
    foreach ($p in $Config.Mess.AclPatterns) { $sum += [int]$p.Pct }
    if ([math]::Abs($sum - 100) -gt 1) {
        throw "Mess.AclPatterns percentages must sum to 100 (currently $sum)."
    }
    # FileClasses pct must sum to 100
    $sum = 0
    foreach ($c in $Config.TimestampModel.FileClasses) { $sum += [int]$c.Pct }
    if ([math]::Abs($sum - 100) -gt 1) {
        throw "TimestampModel.FileClasses percentages must sum to 100 (currently $sum)."
    }
    return $true
}

# Get-DemoConfigNames — load first/last name corpora into a hashtable.
# Source files wrap their arrays as @{ Names = @(...) } since
# Import-PowerShellDataFile requires hashtable roots.
function Get-DemoConfigNames {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$NamesDir)
    $first = Import-PowerShellDataFile -LiteralPath (Join-Path $NamesDir 'first.psd1')
    $last  = Import-PowerShellDataFile -LiteralPath (Join-Path $NamesDir 'last.psd1')
    @{
        First = [string[]]$first.Names
        Last  = [string[]]$last.Names
    }
}
