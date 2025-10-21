# parallel_utilities.psm1 - High-performance parallel processing utilities for Panzura Demo Toolkit
# Provides runspace pools, batch processing, AD caching, and progress aggregation

#region Configuration
$script:DefaultBatchSize = 100
$script:DefaultMaxThreads = [Math]::Min([Environment]::ProcessorCount * 2, 16)
$script:ADCacheExpiration = 300  # 5 minutes in seconds
$script:ProgressReportInterval = 200  # Report progress every N items
#endregion

#region AD Cache Management
$script:ADCache = @{
    Users = @{}
    Groups = @{}
    Domains = @{}
    LastUpdate = [DateTime]::MinValue
}

function Initialize-ADCache {
    [CmdletBinding()]
    param(
        [switch]$Force
    )
    
    $now = Get-Date
    if (-not $Force -and ($now - $script:ADCache.LastUpdate).TotalSeconds -lt $script:ADCacheExpiration) {
        Write-Verbose "AD cache still valid, skipping refresh"
        return
    }
    
    Write-Verbose "Initializing AD cache..."
    
    try {
        # Cache domain info
        $domain = Get-ADDomain -ErrorAction Stop
        $script:ADCache.Domains[$domain.DNSRoot] = @{
            NetBIOSName = $domain.NetBIOSName
            DistinguishedName = $domain.DistinguishedName
        }
        
        # Cache all department groups (GG_*)
        $deptGroups = Get-ADGroup -Filter 'SamAccountName -like "GG_*"' -Properties Members -ErrorAction Stop
        foreach ($group in $deptGroups) {
            $script:ADCache.Groups[$group.SamAccountName] = @{
                DistinguishedName = $group.DistinguishedName
                Members = @($group.Members)
            }
            
            # Cache group members
            if ($group.Members.Count -gt 0 -and $group.Members.Count -lt 1000) {  # Skip very large groups
                try {
                    $members = Get-ADGroupMember -Identity $group.SamAccountName -ErrorAction Stop | 
                               Where-Object { $_.objectClass -eq 'user' } |
                               Get-ADUser -Properties SamAccountName -ErrorAction SilentlyContinue
                    
                    foreach ($member in $members) {
                        $script:ADCache.Users[$member.SamAccountName] = @{
                            DistinguishedName = $member.DistinguishedName
                            Department = $group.SamAccountName -replace '^GG_', ''
                        }
                    }
                } catch {
                    Write-Verbose "Failed to cache members of $($group.SamAccountName): $_"
                }
            }
        }
        
        $script:ADCache.LastUpdate = $now
        Write-Verbose "AD cache initialized with $($script:ADCache.Groups.Count) groups and $($script:ADCache.Users.Count) users"
        
    } catch {
        Write-Warning "Failed to initialize AD cache: $_"
        return $false
    }
    
    return $true
}

function Get-CachedADUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Department
    )
    
    $groupName = "GG_$Department"
    if (-not $script:ADCache.Groups.ContainsKey($groupName)) {
        return $null
    }
    
    # Get users from this department
    $deptUsers = $script:ADCache.Users.GetEnumerator() | 
                 Where-Object { $_.Value.Department -eq $Department } |
                 Select-Object -ExpandProperty Key
    
    if ($deptUsers.Count -eq 0) {
        return $null
    }
    
    # Return random user from department
    return $deptUsers | Get-Random
}

function Get-CachedDomain {
    if ($script:ADCache.Domains.Count -eq 0) {
        Initialize-ADCache
    }
    
    $domain = $script:ADCache.Domains.Values | Select-Object -First 1
    return $domain.NetBIOSName
}
#endregion

#region Runspace Pool Management
function New-RunspacePool {
    [CmdletBinding()]
    param(
        [int]$MinThreads = 1,
        [int]$MaxThreads = $script:DefaultMaxThreads,
        [hashtable]$Variables = @{},
        [string[]]$Modules = @()
    )
    
    Write-Verbose "Creating runspace pool with $MinThreads-$MaxThreads threads"
    
    # Create initial session state
    $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    
    # Add modules
    foreach ($module in $Modules) {
        Write-Verbose "Adding module to session state: $module"
        $sessionState.ImportPSModule($module)
    }
    
    # Add variables
    foreach ($key in $Variables.Keys) {
        Write-Verbose "Adding variable to session state: $key"
        $entry = [System.Management.Automation.Runspaces.SessionStateVariableEntry]::new($key, $Variables[$key], $null)
        $sessionState.Variables.Add($entry)
    }
    
    # Create runspace pool
    $runspacePool = [runspacefactory]::CreateRunspacePool($MinThreads, $MaxThreads, $sessionState, $Host)
    $runspacePool.ApartmentState = [System.Threading.ApartmentState]::MTA
    $runspacePool.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
    $runspacePool.Open()
    
    return $runspacePool
}

function Invoke-ParallelBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$InputObject,
        
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        
        [int]$BatchSize = $script:DefaultBatchSize,
        [int]$MaxThreads = $script:DefaultMaxThreads,
        [hashtable]$Variables = @{},
        [string[]]$Modules = @(),
        [switch]$ShowProgress
    )
    
    $totalItems = $InputObject.Count
    Write-Verbose "Processing $totalItems items in batches of $BatchSize with up to $MaxThreads threads"
    
    # Create runspace pool
    $runspacePool = New-RunspacePool -MinThreads 1 -MaxThreads $MaxThreads -Variables $Variables -Modules $Modules
    
    # Progress tracking
    $progress = [System.Collections.Concurrent.ConcurrentDictionary[string, int]]::new()
    $progress['completed'] = 0
    $progress['errors'] = 0
    $startTime = Get-Date
    
    try {
        # Split input into batches
        $batches = @()
        for ($i = 0; $i -lt $totalItems; $i += $BatchSize) {
            $batch = $InputObject[$i..[Math]::Min($i + $BatchSize - 1, $totalItems - 1)]
            $batches += ,@($batch)
        }
        
        Write-Verbose "Created $($batches.Count) batches"
        
        # Create runspaces for each batch
        $runspaces = @()
        foreach ($batch in $batches) {
            $powershell = [powershell]::Create()
            $powershell.RunspacePool = $runspacePool
            
            # Add script and parameters
            [void]$powershell.AddScript($ScriptBlock)
            [void]$powershell.AddArgument($batch)
            [void]$powershell.AddArgument($progress)
            
            # Start async execution
            $runspaces += @{
                PowerShell = $powershell
                Handle = $powershell.BeginInvoke()
                Batch = $batch
            }
        }
        
        # Monitor progress
        $completed = 0
        while ($runspaces.Where({ -not $_.Handle.IsCompleted }).Count -gt 0) {
            Start-Sleep -Milliseconds 100
            
            # Check for completed runspaces
            foreach ($runspace in $runspaces.Where({ $_.Handle.IsCompleted -and -not $_.Processed })) {
                try {
                    $result = $runspace.PowerShell.EndInvoke($runspace.Handle)
                    $runspace.Result = $result
                } catch {
                    Write-Warning "Batch processing error: $_"
                    $progress['errors'] = $progress['errors'] + $runspace.Batch.Count
                }
                
                $runspace.PowerShell.Dispose()
                $runspace.Processed = $true
                $completed++
            }
            
            # Update progress
            if ($ShowProgress) {
                $currentCount = $progress['completed']
                $errorCount = $progress['errors']
                $elapsed = (Get-Date) - $startTime
                $rate = if ($elapsed.TotalSeconds -gt 0) { $currentCount / $elapsed.TotalSeconds } else { 0 }
                $pct = [Math]::Min(100, [int](100 * $currentCount / $totalItems))
                
                Write-Progress -Activity "Parallel Processing" `
                    -Status "Completed: $currentCount / $totalItems (Errors: $errorCount)" `
                    -PercentComplete $pct `
                    -CurrentOperation "Rate: $([Math]::Round($rate, 1)) items/sec"
            }
        }
        
        # Collect results
        $results = $runspaces | Where-Object { $_.Result } | ForEach-Object { $_.Result }
        return $results
        
    } finally {
        $runspacePool.Close()
        $runspacePool.Dispose()
        
        if ($ShowProgress) {
            Write-Progress -Activity "Parallel Processing" -Completed
        }
    }
}
#endregion

#region Bulk File Operations
function New-BulkSparseFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable[]]$FileSpecs,  # Array of @{Path='...'; SizeKB=123}
        [int]$BatchSize = 50
    )
    
    $results = @()
    
    # Group by directory for efficiency
    $byDirectory = $FileSpecs | Group-Object { Split-Path $_.Path -Parent }
    
    foreach ($dirGroup in $byDirectory) {
        $directory = $dirGroup.Name
        
        # Ensure directory exists
        if (-not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        
        # Process files in batches
        $files = $dirGroup.Group
        for ($i = 0; $i -lt $files.Count; $i += $BatchSize) {
            $batch = $files[$i..[Math]::Min($i + $BatchSize - 1, $files.Count - 1)]
            
            # Create files
            foreach ($spec in $batch) {
                try {
                    # Create file
                    New-Item -ItemType File -Path $spec.Path -Force | Out-Null
                    
                    # Set sparse flag using single fsutil call
                    $null = cmd /c "fsutil sparse setflag `"$($spec.Path)`"" 2>$null
                    
                    if ($LASTEXITCODE -eq 0) {
                        # Set size
                        $targetBytes = [int64]$spec.SizeKB * 1024L
                        $fs = [IO.File]::Open($spec.Path, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None)
                        try {
                            $seekTo = [Math]::Max(0L, $targetBytes - 1)
                            [void]$fs.Seek($seekTo, [IO.SeekOrigin]::Begin)
                            $fs.WriteByte(0)
                        } finally {
                            $fs.Close()
                        }
                        
                        $results += @{ Path = $spec.Path; Success = $true }
                    } else {
                        $results += @{ Path = $spec.Path; Success = $false; Error = "Sparse flag failed" }
                    }
                } catch {
                    $results += @{ Path = $spec.Path; Success = $false; Error = $_.Exception.Message }
                }
            }
        }
    }
    
    return $results
}

function Set-BulkFileAttributes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Paths,
        [System.IO.FileAttributes]$Attributes = 'Normal',
        [int]$BatchSize = 100
    )
    
    $results = @()
    
    for ($i = 0; $i -lt $Paths.Count; $i += $BatchSize) {
        $batch = $Paths[$i..[Math]::Min($i + $BatchSize - 1, $Paths.Count - 1)]
        
        foreach ($path in $batch) {
            try {
                [IO.File]::SetAttributes($path, $Attributes)
                $results += @{ Path = $path; Success = $true }
            } catch {
                $results += @{ Path = $path; Success = $false; Error = $_.Exception.Message }
            }
        }
    }
    
    return $results
}

function Set-BulkTimestamps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable[]]$FileSpecs,  # Array of @{Path='...'; Created=...; Modified=...; Accessed=...}
        [int]$BatchSize = 100
    )
    
    $results = @()
    
    for ($i = 0; $i -lt $FileSpecs.Count; $i += $BatchSize) {
        $batch = $FileSpecs[$i..[Math]::Min($i + $BatchSize - 1, $FileSpecs.Count - 1)]
        
        foreach ($spec in $batch) {
            try {
                if ($spec.Created) { [IO.File]::SetCreationTime($spec.Path, $spec.Created) }
                if ($spec.Modified) { [IO.File]::SetLastWriteTime($spec.Path, $spec.Modified) }
                if ($spec.Accessed) { [IO.File]::SetLastAccessTime($spec.Path, $spec.Accessed) }
                $results += @{ Path = $spec.Path; Success = $true }
            } catch {
                $results += @{ Path = $spec.Path; Success = $false; Error = $_.Exception.Message }
            }
        }
    }
    
    return $results
}
#endregion

#region Progress Aggregation
function New-ProgressAggregator {
    [CmdletBinding()]
    param(
        [int]$TotalItems,
        [string]$Activity = "Processing",
        [int]$UpdateInterval = $script:ProgressReportInterval
    )
    
    return @{
        TotalItems = $TotalItems
        Activity = $Activity
        UpdateInterval = $UpdateInterval
        StartTime = Get-Date
        LastUpdate = [DateTime]::MinValue
        Progress = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    }
}

function Update-ProgressAggregator {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Aggregator,
        
        [int]$Completed,
        [int]$Errors = 0,
        [string]$CurrentOperation = ""
    )
    
    $now = Get-Date
    $Aggregator.Progress['completed'] = $Completed
    $Aggregator.Progress['errors'] = $Errors
    
    # Check if update needed
    if (($now - $Aggregator.LastUpdate).TotalMilliseconds -lt 100) {
        return  # Too soon
    }
    
    $elapsed = ($now - $Aggregator.StartTime).TotalSeconds
    $rate = if ($elapsed -gt 0) { $Completed / $elapsed } else { 0 }
    $remaining = $Aggregator.TotalItems - $Completed
    $eta = if ($rate -gt 0) { $remaining / $rate } else { 0 }
    $pct = [Math]::Min(100, [int](100 * $Completed / $Aggregator.TotalItems))
    
    $status = "Items: $Completed / $($Aggregator.TotalItems) (~$([Math]::Round($rate, 1))/s)"
    if ($Errors -gt 0) { $status += " | Errors: $Errors" }
    
    Write-Progress -Activity $Aggregator.Activity `
        -Status $status `
        -PercentComplete $pct `
        -CurrentOperation $CurrentOperation `
        -SecondsRemaining ([int]$eta)
    
    $Aggregator.LastUpdate = $now
}

function Complete-ProgressAggregator {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Aggregator
    )
    
    Write-Progress -Activity $Aggregator.Activity -Completed
    
    $elapsed = (Get-Date - $Aggregator.StartTime)
    $completed = $Aggregator.Progress['completed']
    $errors = $Aggregator.Progress['errors']
    $rate = if ($elapsed.TotalSeconds -gt 0) { $completed / $elapsed.TotalSeconds } else { 0 }
    
    return @{
        Completed = $completed
        Errors = $errors
        Duration = $elapsed
        Rate = [Math]::Round($rate, 2)
    }
}
#endregion

#region Memory Management
function Get-MemoryUsage {
    $process = Get-Process -Id $PID
    return @{
        WorkingSetMB = [Math]::Round($process.WorkingSet64 / 1MB, 2)
        PrivateMemoryMB = [Math]::Round($process.PrivateMemorySize64 / 1MB, 2)
        VirtualMemoryMB = [Math]::Round($process.VirtualMemorySize64 / 1MB, 2)
    }
}

function Invoke-GarbageCollection {
    [CmdletBinding()]
    param(
        [int]$Generation = 2,
        [switch]$WaitForPendingFinalizers
    )
    
    Write-Verbose "Invoking garbage collection (Generation: $Generation)"
    
    [System.GC]::Collect($Generation)
    
    if ($WaitForPendingFinalizers) {
        [System.GC]::WaitForPendingFinalizers()
        [System.GC]::Collect($Generation)
    }
}
#endregion

#region Utility Functions
function Split-Array {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$InputArray,
        
        [Parameter(Mandatory)]
        [int]$ChunkSize
    )
    
    $chunks = @()
    for ($i = 0; $i -lt $InputArray.Count; $i += $ChunkSize) {
        $chunks += ,@($InputArray[$i..[Math]::Min($i + $ChunkSize - 1, $InputArray.Count - 1)])
    }
    
    return $chunks
}

function Test-IsElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-OptimalThreadCount {
    [CmdletBinding()]
    param(
        [int]$ItemCount,
        [int]$MinThreads = 2,
        [int]$MaxThreads = $script:DefaultMaxThreads,
        [int]$ItemsPerThread = 100
    )
    
    $optimal = [Math]::Ceiling($ItemCount / $ItemsPerThread)
    $optimal = [Math]::Max($MinThreads, $optimal)
    $optimal = [Math]::Min($MaxThreads, $optimal)
    
    return $optimal
}
#endregion

# Export all public functions
Export-ModuleMember -Function @(
    'Initialize-ADCache'
    'Get-CachedADUser'
    'Get-CachedDomain'
    'New-RunspacePool'
    'Invoke-ParallelBatch'
    'New-BulkSparseFiles'
    'Set-BulkFileAttributes'
    'Set-BulkTimestamps'
    'New-ProgressAggregator'
    'Update-ProgressAggregator'
    'Complete-ProgressAggregator'
    'Get-MemoryUsage'
    'Invoke-GarbageCollection'
    'Split-Array'
    'Test-IsElevated'
    'Get-OptimalThreadCount'
)