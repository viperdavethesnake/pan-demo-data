# Get-FileTimestampSet — given a file class and a creation anchor, return
# coherent (CreationTime, LastWriteTime, LastAccessTime) respecting invariants.
#
# Invariants:
#   CreationTime <= LastWriteTime <= LastAccessTime
#   All three <= $NowClamp (to prevent future dates)
function Get-FileTimestampSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][datetime]$Creation,
        [Parameter(Mandatory)][hashtable]$FileClass,   # has WriteGapMin/Max, AccessGapMin/Max
        [datetime]$NowClamp = (Get-Date),
        [System.Random]$Rng = $null
    )
    if (-not $Rng) { $Rng = [System.Random]::new() }

    $ct = $Creation
    if ($ct -gt $NowClamp) { $ct = $NowClamp.AddHours(-1) }

    $writeGapMin = [int]$FileClass.WriteGapMin
    $writeGapMax = [int]$FileClass.WriteGapMax
    if ($writeGapMax -lt $writeGapMin) { $writeGapMax = $writeGapMin }
    $writeGap = if ($writeGapMax -eq $writeGapMin) { $writeGapMin } else { $Rng.Next($writeGapMin, $writeGapMax + 1) }
    $wt = $ct.AddDays($writeGap).AddMinutes($Rng.Next(0, 1440))  # jitter within the day
    if ($wt -gt $NowClamp) {
        # Disperse across the last 7 days instead of pinning to NowClamp.
        # Avoids N files sharing the exact same "Now" value, which looks
        # like contamination to scanners.
        $wt = $NowClamp.AddMinutes(-$Rng.Next(1, 10080))
    }
    if ($wt -lt $ct) { $wt = $ct }

    $accessGapMin = [int]$FileClass.AccessGapMin
    $accessGapMax = [int]$FileClass.AccessGapMax
    if ($accessGapMax -lt $accessGapMin) { $accessGapMax = $accessGapMin }
    $accessGap = if ($accessGapMax -eq $accessGapMin) { $accessGapMin } else { $Rng.Next($accessGapMin, $accessGapMax + 1) }
    $at = $wt.AddDays($accessGap)
    if ($accessGap -gt 0) { $at = $at.AddMinutes($Rng.Next(0, 1440)) }
    if ($at -gt $NowClamp) {
        # Same dispersion rule as write-time clamp.
        $at = $NowClamp.AddMinutes(-$Rng.Next(1, 10080))
    }
    if ($at -lt $wt) { $at = $wt }

    return [pscustomobject]@{
        CreationTime   = $ct
        LastWriteTime  = $wt
        LastAccessTime = $at
    }
}
