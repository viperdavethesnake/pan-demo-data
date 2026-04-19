# Get-NormalSample — Box-Muller transform, integer result.
function Get-NormalSample {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Mean,
        [Parameter(Mandatory)][int]$Std,
        [System.Random]$Rng = $null
    )
    if (-not $Rng) { $Rng = [System.Random]::new() }
    $u1 = [Math]::Max([double]::Epsilon, $Rng.NextDouble())
    $u2 = [Math]::Max([double]::Epsilon, $Rng.NextDouble())
    $z  = [Math]::Sqrt(-2.0 * [Math]::Log($u1)) * [Math]::Sin(2.0 * [Math]::PI * $u2)
    [int]([Math]::Round($Mean + $Std * $z))
}
