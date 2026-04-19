function Invoke-DemoPipeline {
<#
.SYNOPSIS
    Compose the PanzuraDemo phases in a single call.

.DESCRIPTION
    Phases:
      PreFlight   → Test-DemoPrerequisite
      ADPopulate  → New-DemoADPopulation
      Folders     → New-DemoFolderTree
      Files       → New-DemoFile (once per scenario run)
      Orphanize   → Remove-DemoOrphanUser
      Report      → Get-DemoReport
      Reset       → Reset-DemoEnvironment
      All         → PreFlight, ADPopulate, Folders, Files, Orphanize, Report

    Scenarios (config.Scenarios{}) define an array of Files-phase runs.
    CLI overrides (-MaxFiles, -DatePreset, ...) apply to a single Files run
    or each run in the scenario.

.PARAMETER Config
    Path or name; passed to Import-DemoConfig. If omitted, default config.

.PARAMETER Phase
    One or more of: PreFlight, ADPopulate, Folders, Files, Orphanize, Report, Reset, All.

.PARAMETER Scenario
    Name of a scenario from config.Scenarios.

.PARAMETER MaxFiles
.PARAMETER DatePreset
.PARAMETER RecentBias
.PARAMETER MinDate
.PARAMETER MaxDate
    CLI overrides. When set, they apply to EACH run in the scenario.
#>
    [CmdletBinding()]
    param(
        [string]$Config,
        [string[]]$Phase = @('All'),
        [string]$Scenario,
        [Nullable[long]]$MaxFiles,
        [ValidateSet('Uniform','RecentSkew','YearSpread','LegacyMess')][string]$DatePreset,
        [Nullable[int]]$RecentBias,
        [Nullable[datetime]]$MinDate,
        [Nullable[datetime]]$MaxDate,
        [switch]$Parallel
    )

    $cfg = Import-DemoConfig -Path $Config

    # Expand 'All'
    $phases = New-Object System.Collections.Generic.List[string]
    foreach ($p in $Phase) {
        if ($p -ieq 'All') {
            foreach ($x in @('PreFlight','ADPopulate','Folders','Files','Orphanize','Report')) { [void]$phases.Add($x) }
        } else {
            [void]$phases.Add($p)
        }
    }
    # Dedup, preserving order
    $seen = @{}; $ordered = @()
    foreach ($p in $phases) { if (-not $seen.ContainsKey($p)) { $seen[$p] = $true; $ordered += $p } }

    $result = [ordered]@{}

    foreach ($p in $ordered) {
        Write-Host ""
        Write-Host "=== Phase: $p ===" -ForegroundColor Yellow
        switch ($p) {
            'PreFlight' {
                $r = Test-DemoPrerequisite -Config $cfg
                $r.Checks | Format-Table Name, Pass, Detail -AutoSize | Out-Host
                if (-not $r.Pass) { throw "PreFlight failed. Fix the environment and retry." }
                $result.PreFlight = $r
            }
            'ADPopulate' {
                $result.ADPopulate = New-DemoADPopulation -Config $cfg
            }
            'Folders' {
                $result.Folders = New-DemoFolderTree -Config $cfg
            }
            'Files' {
                $runs = @()
                if ($Scenario) {
                    $sc = Get-DemoScenario -Config $cfg -Name $Scenario
                    $runs = @($sc.Runs)
                } else {
                    $runs = @(@{
                        MaxFiles   = $cfg.Files.DefaultCount
                        DatePreset = $cfg.Files.DefaultDatePreset
                        RecentBias = $cfg.Files.DefaultRecentBias
                    })
                }
                # Apply CLI overrides to each run
                $runOut = @()
                foreach ($r in $runs) {
                    $mf  = if ($MaxFiles)    { [long]$MaxFiles }   else { [long]$r.MaxFiles }
                    $dp  = if ($DatePreset)  { $DatePreset }       else { $r.DatePreset }
                    $bias= if ($RecentBias -ne $null) { [int]$RecentBias } elseif ($r.ContainsKey('RecentBias')) { [int]$r.RecentBias } else { [int]$cfg.Files.DefaultRecentBias }
                    $mind= if ($MinDate)     { [datetime]$MinDate } elseif ($r.ContainsKey('MinDate')) { [datetime]$r.MinDate } else { (Get-Date).AddYears(-3) }
                    $maxd= if ($MaxDate)     { [datetime]$MaxDate } elseif ($r.ContainsKey('MaxDate')) { [datetime]$r.MaxDate } else { (Get-Date) }
                    $runOut += (New-DemoFile -Config $cfg -MaxFiles $mf -DatePreset $dp -RecentBias $bias -MinDate $mind -MaxDate $maxd -Parallel:$Parallel)
                }
                $result.Files = $runOut
            }
            'Orphanize' {
                $result.Orphanize = Remove-DemoOrphanUser -Config $cfg -Confirm:$false
            }
            'Report' {
                $result.Report = Get-DemoReport -Config $cfg
            }
            'Reset' {
                $result.Reset = Reset-DemoEnvironment -Config $cfg -Confirm:$false
            }
            default { throw "Unknown phase: $p" }
        }
    }

    return [pscustomobject]$result
}
