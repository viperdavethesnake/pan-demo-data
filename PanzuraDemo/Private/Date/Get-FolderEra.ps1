# Get-FolderEra — draw / resolve a "folder era" date for a given folder.
# Era is used to cluster CreationTime of files in the same folder (T2 coherence).
# Cache is a hashtable keyed by full folder path.
#
# Archive year override: if folder looks like .../Archive/<yyyy>/ and
# ArchiveYearOverrides is true, the era is pinned to mid-year of that year.
function Get-FolderEra {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FolderPath,
        [Parameter(Mandatory)][hashtable]$Cache,
        [Parameter(Mandatory)][datetime]$MinDate,
        [Parameter(Mandatory)][datetime]$MaxDate,
        [Parameter(Mandatory)][string]$DatePreset,
        [int]$RecentBias = 70,
        [bool]$ArchiveYearOverrides = $true,
        [System.Random]$Rng = $null
    )
    if ($Cache.ContainsKey($FolderPath)) {
        return [datetime]$Cache[$FolderPath]
    }
    if ($ArchiveYearOverrides) {
        $m = [regex]::Match($FolderPath, '[\\/]Archive[\\/](\d{4})([\\/]|$)')
        if ($m.Success) {
            $y = [int]$m.Groups[1].Value
            $era = [datetime]::new($y, 6, 15)
            if ($era -lt $MinDate) { $era = $MinDate }
            if ($era -gt $MaxDate) { $era = $MaxDate }
            $Cache[$FolderPath] = $era
            return $era
        }
    }
    $era = Get-RealisticDate -MinDate $MinDate -MaxDate $MaxDate -Preset $DatePreset -Bias $RecentBias -Rng $Rng
    $Cache[$FolderPath] = $era
    return $era
}

# Get-EraJitteredDate — apply ± window around era to get a file-level CT.
function Get-EraJitteredDate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][datetime]$Era,
        [Parameter(Mandatory)][int]$WindowDays,
        [datetime]$NowClamp = (Get-Date),
        [datetime]$MinClamp = [datetime]::new(1990,1,1),
        [System.Random]$Rng = $null
    )
    if (-not $Rng) { $Rng = [System.Random]::new() }
    $jitterDays = ($Rng.NextDouble() * 2 - 1) * $WindowDays
    $result = $Era.AddDays($jitterDays)
    if ($result -gt $NowClamp) { $result = $NowClamp.AddHours(-$Rng.Next(1, 24)) }
    if ($result -lt $MinClamp) { $result = $MinClamp }
    return $result
}
