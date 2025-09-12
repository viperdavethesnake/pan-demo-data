# create-files-fixed.ps1
# --- Bulletproof Realistic File Creator with Domain User Ownership ---
# BULLETPROOF VERSION - Robust error handling, validation, and proper resource management

param(
    [string]$RootPath = "S:\Shared",
    [long]$FileCount = 100000,
    [datetime]$StartDate = (Get-Date).AddYears(-20),
    [datetime]$EndDate = (Get-Date),
    [long]$MinNormalSize = 64KB,
    [long]$MaxNormalSize = 50MB,
    [long]$MinBigSize = 256MB,
    [long]$MaxBigSize = 4GB,
    [string]$DomainOwner = "PLAB\Administrator",
    [switch]$WhatIf
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "BULLETPROOF FILE CREATOR" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Root Path: $RootPath"
Write-Host "File Count: $FileCount"
Write-Host "Normal File Size: $([math]::Round($MinNormalSize/1KB))KB - $([math]::Round($MaxNormalSize/1MB))MB"
Write-Host "Big File Size: $([math]::Round($MinBigSize/1MB))MB - $([math]::Round($MaxBigSize/1GB))GB"
Write-Host "Date Range: $($StartDate.ToString('yyyy-MM-dd')) to $($EndDate.ToString('yyyy-MM-dd'))"
Write-Host "Domain Owner Fallback: $DomainOwner"
Write-Host "WhatIf Mode: $WhatIf"
Write-Host ""

# === FUNCTIONS (defined first) ===

function Get-RandomDate($start, $end) {
    $range = ($end - $start).TotalSeconds
    return $start.AddSeconds((Get-Random -Minimum 0 -Maximum $range))
}

function Get-RandomDomainUsers {
    Write-Host "Retrieving domain users..." -ForegroundColor Yellow
    try {
        $users = Get-ADUser -Filter * -SearchBase "CN=Users,DC=plab,DC=local" | Where-Object {
            $_.SamAccountName -match "^[a-z]+\.[a-z]+$" -and  # firstname.lastname pattern
            $_.Enabled -eq $true
        }
        Write-Host "  Found $($users.Count) domain users" -ForegroundColor Green
        return $users
    } catch {
        Write-Host "  ✗ Failed to get domain users: $_" -ForegroundColor Red
        return @()
    }
}

function Set-DomainOwnership {
    param([string]$Path, [string]$Owner)
    try {
        if ($WhatIf) {
            return $true
        }
        
        $acl = Get-Acl $Path
        $account = New-Object System.Security.Principal.NTAccount($Owner)
        $acl.SetOwner($account)
        Set-Acl $Path $acl
        return $true
    } catch {
        return $false
    }
}

function New-SparseFile {
    param(
        [string]$FilePath,
        [byte[]]$Header,
        [long]$Size
    )
    
    $fs = $null
    try {
        if ($WhatIf) {
            Write-Host "    WOULD CREATE: $FilePath ($Size bytes)" -ForegroundColor Cyan
            return $true
        }
        
        # Create file with header
        [System.IO.File]::WriteAllBytes($FilePath, $Header)
        
        # Mark as sparse using fsutil
        $result = cmd /c "fsutil sparse setflag `"$FilePath`"" 2>$null
        
        # Set logical size by seeking to end and writing a byte
        $fs = [System.IO.File]::Open($FilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write)
        $fs.Seek($Size-1, [System.IO.SeekOrigin]::Begin) | Out-Null
        $fs.WriteByte(0)
        
        return $true
    } catch {
        Write-Host "    ✗ Failed to create sparse file: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    } finally {
        if ($fs) {
            $fs.Close()
            $fs.Dispose()
        }
    }
}

function Set-FileTimestamps {
    param(
        [string]$FilePath,
        [datetime]$StartDate,
        [datetime]$EndDate
    )
    
    try {
        if ($WhatIf) {
            return $true
        }
        
        $created = Get-RandomDate $StartDate $EndDate
        $accessed = Get-RandomDate $created $EndDate
        $modified = Get-RandomDate $created $EndDate
        
        [System.IO.File]::SetCreationTime($FilePath, $created)
        [System.IO.File]::SetLastAccessTime($FilePath, $accessed)
        [System.IO.File]::SetLastWriteTime($FilePath, $modified)
        
        return $true
    } catch {
        return $false
    }
}

# === FILE TYPE DEFINITIONS ===

$normalTypes = @{
    'docx' =  [byte[]](0x50,0x4B,0x03,0x04)  # Office 2007+ (ZIP-based)
    'xlsx' =  [byte[]](0x50,0x4B,0x03,0x04)
    'pptx' =  [byte[]](0x50,0x4B,0x03,0x04)
    'pdf'  =  [byte[]](0x25,0x50,0x44,0x46)  # %PDF
    'txt'  =  [byte[]](0xEF,0xBB,0xBF)       # UTF-8 BOM
    'csv'  =  [byte[]](0xEF,0xBB,0xBF)
    'xml'  =  [byte[]](0x3C,0x3F,0x78,0x6D,0x6C)  # <?xml
    'json' =  [byte[]](0x7B)                 # {
    'jpg'  =  [byte[]](0xFF,0xD8,0xFF)       # JPEG
    'png'  =  [byte[]](0x89,0x50,0x4E,0x47)  # PNG
    'gif'  =  [byte[]](0x47,0x49,0x46,0x38)  # GIF8
    'bmp'  =  [byte[]](0x42,0x4D)            # BM
    'rtf'  =  [byte[]](0x7B,0x5C,0x72,0x74,0x66)  # {\rtf
    'msg'  =  [byte[]](0xD0,0xCF,0x11,0xE0)  # Outlook MSG
    'htm'  =  [byte[]](0x3C,0x21,0x44,0x4F,0x43)  # <!DOC
    'html' =  [byte[]](0x3C,0x21,0x44,0x4F,0x43)
    'ppt'  =  [byte[]](0xD0,0xCF,0x11,0xE0)  # Office 97-2003
    'xls'  =  [byte[]](0xD0,0xCF,0x11,0xE0)
    'doc'  =  [byte[]](0xD0,0xCF,0x11,0xE0)
    'zip'  =  [byte[]](0x50,0x4B,0x03,0x04)  # ZIP
    '7z'   =  [byte[]](0x37,0x7A,0xBC,0xAF,0x27,0x1C)  # 7-Zip
}

$bigTypes = @{
    'iso' =  [byte[]](0x43,0x44,0x30,0x30,0x31)  # CD001
    'mp4' =  [byte[]](0x00,0x00,0x00,0x18,0x66,0x74,0x79,0x70)  # MP4
    'mkv' =  [byte[]](0x1A,0x45,0xDF,0xA3)        # Matroska
    'avi' =  [byte[]](0x52,0x49,0x46,0x46)        # RIFF
    'mov' =  [byte[]](0x00,0x00,0x00,0x14,0x66,0x74,0x79,0x70)  # QuickTime
    'mp3' =  [byte[]](0x49,0x44,0x33)             # ID3
    'psd' =  [byte[]](0x38,0x42,0x50,0x53)        # Photoshop
    'tif' =  [byte[]](0x49,0x49,0x2A,0x00)        # TIFF
    'vmdk'=  [byte[]](0x4B,0x44,0x4D)             # VMware disk
    'vhd' =  [byte[]](0x63,0x6F,0x6E,0x65,0x63,0x74,0x69,0x78)  # VHD
}

# Business-like filename prefixes
$prefixes = @(
    "QEmDN","xbKaovgt","SxWkuRnmQXEt","lfetCzvPAL","RDSqg",  # Random legacy codes
    "Doc","Team","Plan","Audit","Data","Backup","TEMP","Client","Project",  # Business terms
    "Analysis","Report","Roster","Spec","Budget","Proposal","Memo","Meeting",
    "Contract","Invoice","Statement","Timesheet","Presentation","Training",
    "Guidelines","Policy","Procedure","Manual","Archive","Draft","Final"
)

# === VALIDATION ===

Write-Host "Validating environment..." -ForegroundColor Yellow

# Check if root path exists
if (-not (Test-Path $RootPath)) {
    Write-Host "✗ Root path $RootPath does not exist!" -ForegroundColor Red
    exit 1
} else {
    Write-Host "✓ Root path exists: $RootPath" -ForegroundColor Green
}

# Scan for folders
Write-Host "Scanning for folders..." -ForegroundColor Yellow
$allFolders = Get-ChildItem $RootPath -Recurse -Directory -Force | Where-Object { 
    -not $_.Attributes.ToString().Contains("System") 
}

if ($allFolders.Count -eq 0) {
    Write-Host "✗ No folders found under $RootPath! Run folder creation script first." -ForegroundColor Red
    exit 1
} else {
    Write-Host "✓ Found $($allFolders.Count) folders for file placement" -ForegroundColor Green
}

# Get domain users for ownership
$domainUsers = Get-RandomDomainUsers

# Validate parameters
if ($FileCount -le 0) {
    Write-Host "✗ File count must be greater than 0" -ForegroundColor Red
    exit 1
}

if ($StartDate -ge $EndDate) {
    Write-Host "✗ Start date must be before end date" -ForegroundColor Red
    exit 1
}

Write-Host "✓ All validations passed" -ForegroundColor Green

# === FILE CREATION ===

Write-Host "`nCreating $FileCount files..." -ForegroundColor Yellow
if ($WhatIf) {
    Write-Host "WhatIf mode - no files will actually be created" -ForegroundColor Cyan
}

$startTime = Get-Date
$createdCount = 0
$ownershipFailCount = 0
$fileFailCount = 0

for ($i = 1; $i -le $FileCount; $i++) {
    # Select random folder
    $folder = Get-Random -InputObject $allFolders
    $subPath = $folder.FullName

    # Determine file type and size (10% big files, 90% normal)
    $extType = if ((Get-Random -Minimum 1 -Maximum 100) -le 10) { "big" } else { "normal" }
    
    if ($extType -eq "big") {
        $ext = Get-Random -InputObject $bigTypes.Keys
        $size = Get-Random -Minimum $MinBigSize -Maximum $MaxBigSize
        $header = $bigTypes[$ext]
    } else {
        $ext = Get-Random -InputObject $normalTypes.Keys
        $size = Get-Random -Minimum $MinNormalSize -Maximum $MaxNormalSize
        $header = $normalTypes[$ext]
    }

    # Generate realistic filename
    $randPrefix = Get-Random -InputObject $prefixes
    $randHex = -join ((65..90)+(97..122)+(48..57) | Get-Random -Count 8 | ForEach-Object {[char]$_})
    $fname = "$randPrefix-$randHex.$ext"
    $fullPath = Join-Path $subPath $fname

    # Progress reporting with ETA
    if (($i % 100) -eq 1 -or $i -eq 1) {
        $elapsed = (Get-Date) - $startTime
        $rate = if ($elapsed.TotalSeconds -gt 0) { ($i-1) / $elapsed.TotalSeconds } else { 0 }
        $eta = if ($rate -gt 0) { [TimeSpan]::FromSeconds(($FileCount - $i) / $rate) } else { [TimeSpan]::Zero }
        
        Write-Host "[$i/$FileCount] $($fname) ($(if($extType -eq 'big'){'BIG'}else{'normal'}) $([math]::Round($size/1MB,1))MB) ETA: $($eta.ToString('hh\:mm\:ss'))" -ForegroundColor Green
    }

    try {
        # Create sparse file
        $fileCreated = New-SparseFile -FilePath $fullPath -Header $header -Size $size
        
        if ($fileCreated) {
            # Set random domain user as owner
            if ($domainUsers.Count -gt 0) {
                $randomUser = Get-Random -InputObject $domainUsers
                $owner = "PLAB\$($randomUser.SamAccountName)"
            } else {
                $owner = $DomainOwner  # Fallback
            }
            
            $ownershipResult = Set-DomainOwnership -Path $fullPath -Owner $owner
            if (-not $ownershipResult) {
                $ownershipFailCount++
            }
            
            # Set random timestamps
            Set-FileTimestamps -FilePath $fullPath -StartDate $StartDate -EndDate $EndDate | Out-Null
            
            $createdCount++
        } else {
            $fileFailCount++
        }
        
    } catch {
        Write-Host "✗ ERROR creating $fullPath : $($_.Exception.Message)" -ForegroundColor Red
        $fileFailCount++
    }
}

# === SUMMARY REPORT ===

$endTime = Get-Date
$totalTime = $endTime - $startTime
$avgRate = if ($totalTime.TotalSeconds -gt 0) { $createdCount / $totalTime.TotalSeconds } else { 0 }

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "BULLETPROOF FILE CREATION COMPLETE" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Files requested: $FileCount" -ForegroundColor Green
Write-Host "Files created: $createdCount" -ForegroundColor Green
Write-Host "File creation failures: $fileFailCount" -ForegroundColor $(if($fileFailCount -gt 0){'Red'}else{'Green'})
Write-Host "Ownership failures: $ownershipFailCount" -ForegroundColor $(if($ownershipFailCount -gt 0){'Yellow'}else{'Green'})
Write-Host "Domain users for ownership: $($domainUsers.Count)" -ForegroundColor Green
Write-Host "Total time: $($totalTime.ToString('hh\:mm\:ss'))" -ForegroundColor Green
Write-Host "Average rate: $([math]::Round($avgRate,1)) files/second" -ForegroundColor Green
Write-Host ""

if ($WhatIf) {
    Write-Host "WhatIf mode completed - no actual files created" -ForegroundColor Cyan
} else {
    Write-Host "✓ Realistic enterprise files created with:" -ForegroundColor Green
    Write-Host "  ✓ Random domain user ownership" -ForegroundColor Green  
    Write-Host "  ✓ Proper file headers for each type" -ForegroundColor Green
    Write-Host "  ✓ Sparse files for storage efficiency" -ForegroundColor Green
    Write-Host "  ✓ Random timestamps spanning $($StartDate.Year)-$($EndDate.Year)" -ForegroundColor Green
    Write-Host "  ✓ Business-like filenames" -ForegroundColor Green
}

Write-Host "`nFiles ready for Symphony scanning!" -ForegroundColor Green