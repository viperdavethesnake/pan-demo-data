# Get-RealisticDate — pick a date based on a preset.
# Presets:
#   Uniform     — uniform in [MinDate, MaxDate]
#   RecentSkew  — power-law toward MaxDate; Bias in [0,100], higher=more recent
#   YearSpread  — pick a uniform year in range, then uniform within that year
#   LegacyMess  — 3-era weighted: 40% first third, 30% middle third, 30% last third
function Get-RealisticDate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][datetime]$MinDate,
        [Parameter(Mandatory)][datetime]$MaxDate,
        [ValidateSet('Uniform','RecentSkew','YearSpread','LegacyMess')]
        [string]$Preset = 'RecentSkew',
        [int]$Bias = 70,
        [System.Random]$Rng = $null
    )
    if (-not $Rng) { $Rng = [System.Random]::new() }
    $span = ($MaxDate - $MinDate).TotalDays
    if ($span -le 0) { return $MinDate }

    switch ($Preset) {
        'Uniform' {
            $offset = $Rng.NextDouble() * $span
            return $MinDate.AddDays($offset)
        }
        'RecentSkew' {
            $biasNorm = [Math]::Max(0, [Math]::Min(100, $Bias)) / 100.0
            # Higher bias -> smaller exponent -> more mass near 0 -> closer to MaxDate
            $exp = 2.0 - $biasNorm
            $skew = [Math]::Pow($Rng.NextDouble(), $exp)
            $offset = $skew * $span
            return $MaxDate.AddDays(-$offset)
        }
        'YearSpread' {
            $years = [Math]::Max(1, [int][Math]::Floor($span / 365.25))
            $yearPick = $Rng.Next(0, $years)
            $yearStart = $MinDate.AddYears($yearPick)
            $yearEnd   = $yearStart.AddYears(1)
            if ($yearEnd -gt $MaxDate) { $yearEnd = $MaxDate }
            $yearSpan = ($yearEnd - $yearStart).TotalDays
            if ($yearSpan -le 0) { return $yearStart }
            return $yearStart.AddDays($Rng.NextDouble() * $yearSpan)
        }
        'LegacyMess' {
            $t1 = $MinDate.AddDays($span * (1.0/3.0))
            $t2 = $MinDate.AddDays($span * (2.0/3.0))
            $roll = $Rng.NextDouble()
            if     ($roll -lt 0.4) { $a = $MinDate; $b = $t1 }
            elseif ($roll -lt 0.7) { $a = $t1;      $b = $t2 }
            else                   { $a = $t2;      $b = $MaxDate }
            $sub = ($b - $a).TotalDays
            if ($sub -le 0) { return $a }
            return $a.AddDays($Rng.NextDouble() * $sub)
        }
    }
    return $MinDate
}
