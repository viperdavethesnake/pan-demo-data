# Get-WeightedChoice — pick a key from a weight map proportional to weights.
# Map values may be ints or doubles.
function Get-WeightedChoice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Weights,
        [System.Random]$Rng = $null
    )
    if (-not $Rng) { $Rng = [System.Random]::new() }
    if ($Weights.Count -eq 0) { throw "Get-WeightedChoice: empty weight map." }
    $total = 0.0
    foreach ($v in $Weights.Values) { $total += [double]$v }
    if ($total -le 0) { throw "Get-WeightedChoice: total weight is zero or negative." }
    $pick = $Rng.NextDouble() * $total
    $acc  = 0.0
    $last = $null
    foreach ($k in $Weights.Keys) {
        $acc += [double]$Weights[$k]
        $last = $k
        if ($pick -lt $acc) { return $k }
    }
    return $last   # floating-point edge fallback
}

# Get-WeightedChoiceFromPctArray — same idea, for array-of-records with Pct property.
# Records look like @{ Name='X'; Pct=55; <other keys> }. Returns the full record.
function Get-WeightedChoiceFromPctArray {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][array]$Records,
        [System.Random]$Rng = $null
    )
    if (-not $Rng) { $Rng = [System.Random]::new() }
    if ($Records.Count -eq 0) { throw "Get-WeightedChoiceFromPctArray: empty." }
    $total = 0.0
    foreach ($r in $Records) { $total += [double]$r.Pct }
    $pick = $Rng.NextDouble() * $total
    $acc  = 0.0
    foreach ($r in $Records) {
        $acc += [double]$r.Pct
        if ($pick -lt $acc) { return $r }
    }
    return $Records[-1]
}
