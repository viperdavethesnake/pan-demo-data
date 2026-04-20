$ErrorActionPreference = 'Stop'
$log = 'C:\Users\Administrator\Documents\pan-demo-data\build-10M.log'
Remove-Item $log -ErrorAction SilentlyContinue

function Write-Stage([string]$Msg) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Msg"
    Write-Host $line -ForegroundColor Cyan
    Add-Content -Path $log -Value $line
}

Write-Stage "START build-10M v4.1.0"
Import-Module 'C:\Users\Administrator\Documents\pan-demo-data\PanzuraDemo\PanzuraDemo.psd1' -Force

$total = [Diagnostics.Stopwatch]::StartNew()

$today     = Get-Date
$tenYrAgo  = $today.AddYears(-10)
$deadStart = [datetime]'2019-01-01'
$deadEnd   = [datetime]'2019-12-31'

Write-Stage "Date windows: -10y=$($tenYrAgo.ToString('yyyy-MM-dd'))  Deadbeat=$($deadStart.ToString('yyyy-MM-dd'))..$($deadEnd.ToString('yyyy-MM-dd'))"

function Invoke-Phase {
    param([string]$Label, [scriptblock]$Action)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Write-Stage "PHASE START: $Label"
    & $Action *>&1 | Tee-Object -FilePath $log -Append
    $sw.Stop()
    Write-Stage "PHASE DONE:  $Label  (elapsed $($sw.Elapsed))"
}

Invoke-Phase 'PreFlight+ADPopulate+Folders' {
    Invoke-DemoPipeline -Config default -Phase PreFlight,ADPopulate,Folders
}

Invoke-Phase 'L1: LegacyMess 3.5M (-10y..now)' {
    Invoke-DemoPipeline -Config default -Phase Files `
        -MaxFiles 3500000 -DatePreset LegacyMess -MinDate $tenYrAgo -MaxDate $today
}

Invoke-Phase 'L2: YearSpread 3.0M (-10y..now)' {
    Invoke-DemoPipeline -Config default -Phase Files `
        -MaxFiles 3000000 -DatePreset YearSpread -MinDate $tenYrAgo -MaxDate $today
}

Invoke-Phase 'L3: RecentSkew 3.0M bias=30 (default -3y..now)' {
    Invoke-DemoPipeline -Config default -Phase Files `
        -MaxFiles 3000000 -DatePreset RecentSkew -RecentBias 30
}

Invoke-Phase 'L4: Deadbeat Uniform 0.5M (2019 only)' {
    Invoke-DemoPipeline -Config default -Phase Files `
        -MaxFiles 500000 -DatePreset Uniform -MinDate $deadStart -MaxDate $deadEnd
}

Invoke-Phase 'Orphanize+Report' {
    Invoke-DemoPipeline -Config default -Phase Orphanize,Report
}

$total.Stop()
Write-Stage "TOTAL ELAPSED: $($total.Elapsed)"
Write-Stage "END"
