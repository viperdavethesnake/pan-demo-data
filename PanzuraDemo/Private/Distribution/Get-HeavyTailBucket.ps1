# Get-HeavyTailBucket — pick a bucket (Empty/Small/Med/Large/Mega/Ultra), then
# sample a file count uniformly within the bucket's [Min, Max].
function Get-HeavyTailBucket {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][array]$Distribution,
        [System.Random]$Rng = $null
    )
    if (-not $Rng) { $Rng = [System.Random]::new() }
    $bucket = Get-WeightedChoiceFromPctArray -Records $Distribution -Rng $Rng
    $min = [int]$bucket.Min
    $max = [int]$bucket.Max
    if ($max -lt $min) { $max = $min }
    if ($min -eq $max) { $count = $min }
    else { $count = $Rng.Next($min, $max + 1) }
    [pscustomobject]@{ Bucket = $bucket.Name; Count = $count }
}
