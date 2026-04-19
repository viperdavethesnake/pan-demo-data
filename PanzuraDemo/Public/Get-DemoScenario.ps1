function Get-DemoScenario {
<#
.SYNOPSIS
    List or fetch named scenarios from a loaded config.

.PARAMETER Config
    Config hashtable from Import-DemoConfig.

.PARAMETER Name
    Specific scenario name. If omitted, returns all scenarios as an array of PSCustomObjects.

.OUTPUTS
    PSCustomObject with .Name, .Description, .Runs.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [string]$Name
    )
    $out = foreach ($k in $Config.Scenarios.Keys) {
        $s = $Config.Scenarios[$k]
        [pscustomobject]@{
            Name        = $k
            Description = $s.Description
            Runs        = $s.Runs
        }
    }
    if ($Name) {
        $hit = $out | Where-Object { $_.Name -ieq $Name }
        if (-not $hit) { throw "Scenario '$Name' not found. Known: $($out.Name -join ', ')" }
        return $hit
    }
    return $out
}
