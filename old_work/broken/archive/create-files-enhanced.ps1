# create-files-enhanced.ps1
# --- ENHANCED Realistic File Creator with Smart Logic ---
# ENHANCED VERSION - Department-aware, weighted distribution, realistic sizes, temporal logic

param(
    [string]$RootPath = "S:\Shared",
    [long]$FileCount = 100000,
    [datetime]$StartDate = (Get-Date).AddYears(-20),
    [datetime]$EndDate = (Get-Date),
    [string]$DomainOwner = "PLAB\Administrator",
    [switch]$WhatIf
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "ENHANCED INTELLIGENT FILE CREATOR" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Root Path: $RootPath"
Write-Host "File Count: $FileCount"
Write-Host "Date Range: $($StartDate.ToString('yyyy-MM-dd')) to $($EndDate.ToString('yyyy-MM-dd'))"
Write-Host "Domain Owner Fallback: $DomainOwner"
Write-Host "WhatIf Mode: $WhatIf"
Write-Host ""

# === FUNCTIONS ===

function Get-RandomDate($start, $end) {
    $range = ($end - $start).TotalSeconds
    return $start.AddSeconds((Get-Random -Minimum 0 -Maximum $range))
}

function Get-RandomDomainUsers {
    Write-Host "Retrieving domain users..." -ForegroundColor Yellow
    try {
        $users = Get-ADUser -Filter * -SearchBase "CN=Users,DC=plab,DC=local" | Where-Object {
            $_.SamAccountName -match "^[a-z]+\.[a-z]+$" -and
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
        if ($WhatIf) { return $true }
        $acl = Get-Acl $Path
        $account = New-Object System.Security.Principal.NTAccount($Owner)
        $acl.SetOwner($account)
        Set-Acl $Path $acl
        return $true
    } catch {
        return $false
    }
}

function Get-DepartmentFromPath {
    param([string]$FolderPath)
    
    $pathParts = $FolderPath -split '\\'
    foreach ($part in $pathParts) {
        if ($part -in @('HR','Finance','Engineering','Sales','Marketing','Support','Legal','IT','Accounting','PreSales')) {
            return $part
        }
    }
    return 'General'
}

function Get-FileEra {
    param([datetime]$FileDate)
    
    $year = $FileDate.Year
    if ($year -le 2010) { return 'Legacy' }
    elseif ($year -le 2015) { return 'Modern' }
    else { return 'Current' }
}

function Get-SmartFileType {
    param(
        [string]$Department,
        [string]$Era,
        [bool]$IsBigFile = $false
    )
    
    # Department-specific file type preferences
    $departmentTypes = @{
        'HR' = @{
            'Legacy'  = @('doc','xls','rtf','txt','pdf')
            'Modern'  = @('docx','xlsx','pdf','msg','rtf')
            'Current' = @('docx','xlsx','pdf','msg','json')
        }
        'Finance' = @{
            'Legacy'  = @('xls','doc','csv','txt','pdf')
            'Modern'  = @('xlsx','docx','csv','pdf','xml')
            'Current' = @('xlsx','csv','json','pdf','docx')
        }
        'Engineering' = @{
            'Legacy'  = @('doc','txt','zip','bmp','pdf')
            'Modern'  = @('docx','pdf','zip','xml','jpg')
            'Current' = @('json','xml','zip','pdf','txt')
        }
        'Marketing' = @{
            'Legacy'  = @('ppt','doc','bmp','gif','jpg')
            'Modern'  = @('pptx','docx','jpg','png','pdf')
            'Current' = @('pptx','png','jpg','mp4','pdf')
        }
        'Sales' = @{
            'Legacy'  = @('doc','xls','ppt','pdf','msg')
            'Modern'  = @('docx','xlsx','pptx','pdf','msg')
            'Current' = @('docx','xlsx','pdf','msg','json')
        }
        'IT' = @{
            'Legacy'  = @('txt','xml','zip','iso','doc')
            'Modern'  = @('xml','json','zip','iso','vmdk')
            'Current' = @('json','xml','zip','txt','vhd')
        }
        'Legal' = @{
            'Legacy'  = @('doc','rtf','pdf','txt','msg')
            'Modern'  = @('docx','pdf','msg','rtf','xml')
            'Current' = @('pdf','docx','msg','json','xml')
        }
        'Accounting' = @{
            'Legacy'  = @('xls','doc','csv','pdf','txt')
            'Modern'  = @('xlsx','docx','csv','pdf','xml')
            'Current' = @('xlsx','csv','json','pdf','xml')
        }
        'Support' = @{
            'Legacy'  = @('doc','txt','msg','htm','pdf')
            'Modern'  = @('docx','msg','html','pdf','xml')
            'Current' = @('json','msg','html','pdf','txt')
        }
        'General' = @{
            'Legacy'  = @('doc','xls','txt','jpg','pdf')
            'Modern'  = @('docx','xlsx','pdf','jpg','zip')
            'Current' = @('docx','xlsx','pdf','png','json')
        }
    }
    
    # Big file types (10% of files)
    $bigFileTypes = @{
        'Legacy'  = @('iso','avi','tif','psd')
        'Modern'  = @('iso','mp4','mkv','psd')
        'Current' = @('mp4','mkv','vmdk','vhd')
    }
    
    if ($IsBigFile) {
        $availableTypes = if ($bigFileTypes.ContainsKey($Era)) { 
            $bigFileTypes[$Era] 
        } else { 
            $bigFileTypes['Current']  # Fallback
        }
    } else {
        $availableTypes = if ($departmentTypes.ContainsKey($Department) -and $departmentTypes[$Department].ContainsKey($Era)) { 
            $departmentTypes[$Department][$Era] 
        } else { 
            $departmentTypes['General'][$Era]  # Fallback
        }
    }
    
    return Get-Random -InputObject $availableTypes
}

function New-EnhancedSparseFile {
    param(
        [string]$FilePath,
        [string]$FileType,
        [long]$Size
    )
    
    # Enhanced file headers with longer, more realistic signatures
    $enhancedHeaders = @{
        # Office Documents
        'docx' = [byte[]](0x50,0x4B,0x03,0x04,0x14,0x00,0x06,0x00,0x08,0x00,0x00,0x00,0x21,0x00)  # ZIP+Office
        'xlsx' = [byte[]](0x50,0x4B,0x03,0x04,0x14,0x00,0x06,0x00,0x08,0x00,0x00,0x00,0x21,0x00)
        'pptx' = [byte[]](0x50,0x4B,0x03,0x04,0x14,0x00,0x06,0x00,0x08,0x00,0x00,0x00,0x21,0x00)
        
        # Legacy Office
        'doc'  = [byte[]](0xD0,0xCF,0x11,0xE0,0xA1,0xB1,0x1A,0xE1,0x00,0x00,0x00,0x00)  # OLE2 Document
        'xls'  = [byte[]](0xD0,0xCF,0x11,0xE0,0xA1,0xB1,0x1A,0xE1,0x00,0x00,0x00,0x00)
        'ppt'  = [byte[]](0xD0,0xCF,0x11,0xE0,0xA1,0xB1,0x1A,0xE1,0x00,0x00,0x00,0x00)
        
        # PDF with version
        'pdf'  = [byte[]](0x25,0x50,0x44,0x46,0x2D,0x31,0x2E,0x34,0x0D,0x0A,0x25,0xE2,0xE3,0xCF,0xD3)  # %PDF-1.4
        
        # Text files with BOM
        'txt'  = [byte[]](0xEF,0xBB,0xBF,0x54,0x68,0x69,0x73,0x20,0x69,0x73,0x20,0x61)  # UTF-8 BOM + "This is a"
        'csv'  = [byte[]](0xEF,0xBB,0xBF,0x44,0x61,0x74,0x65,0x2C,0x4E,0x61,0x6D,0x65)  # UTF-8 BOM + "Date,Name"
        'xml'  = [byte[]](0x3C,0x3F,0x78,0x6D,0x6C,0x20,0x76,0x65,0x72,0x73,0x69,0x6F,0x6E,0x3D,0x22,0x31,0x2E,0x30,0x22)  # <?xml version="1.0"
        'json' = [byte[]](0x7B,0x0D,0x0A,0x20,0x20,0x22,0x76,0x65,0x72,0x73,0x69,0x6F,0x6E,0x22)  # {\r\n  "version"
        
        # Images with full headers
        'jpg'  = [byte[]](0xFF,0xD8,0xFF,0xE0,0x00,0x10,0x4A,0x46,0x49,0x46,0x00,0x01,0x01,0x01)  # JFIF
        'png'  = [byte[]](0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52)  # PNG+IHDR
        'gif'  = [byte[]](0x47,0x49,0x46,0x38,0x39,0x61,0x01,0x00,0x01,0x00,0xF0,0x00,0x00)  # GIF89a
        'bmp'  = [byte[]](0x42,0x4D,0x36,0x00,0x0C,0x00,0x00,0x00,0x00,0x00,0x36,0x00,0x00,0x00)  # BM+size
        
        # Email/Web
        'msg'  = [byte[]](0xD0,0xCF,0x11,0xE0,0xA1,0xB1,0x1A,0xE1,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00)  # Outlook MSG
        'htm'  = [byte[]](0x3C,0x21,0x44,0x4F,0x43,0x54,0x59,0x50,0x45,0x20,0x68,0x74,0x6D,0x6C,0x3E)  # <!DOCTYPE html>
        'html' = [byte[]](0x3C,0x21,0x44,0x4F,0x43,0x54,0x59,0x50,0x45,0x20,0x68,0x74,0x6D,0x6C,0x3E)
        
        # Rich Text
        'rtf'  = [byte[]](0x7B,0x5C,0x72,0x74,0x66,0x31,0x5C,0x61,0x6E,0x73,0x69,0x5C,0x64,0x65,0x66,0x66)  # {\rtf1\ansi\deff
        
        # Archives
        'zip'  = [byte[]](0x50,0x4B,0x03,0x04,0x14,0x00,0x00,0x00,0x08,0x00,0x00,0x00,0x00,0x00)  # ZIP
        '7z'   = [byte[]](0x37,0x7A,0xBC,0xAF,0x27,0x1C,0x00,0x04,0x5C,0x24,0x06,0xF1,0x07,0x99)  # 7-Zip
        
        # Media/Big Files
        'iso'  = [byte[]](0x43,0x44,0x30,0x30,0x31,0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00)  # CD001
        'mp4'  = [byte[]](0x00,0x00,0x00,0x18,0x66,0x74,0x79,0x70,0x6D,0x70,0x34,0x31,0x00,0x00,0x00,0x00)  # ftyp mp41
        'mkv'  = [byte[]](0x1A,0x45,0xDF,0xA3,0x93,0x42,0x82,0x88,0x6D,0x61,0x74,0x72,0x6F,0x73,0x6B,0x61)  # Matroska
        'avi'  = [byte[]](0x52,0x49,0x46,0x46,0x00,0x00,0x00,0x00,0x41,0x56,0x49,0x20,0x4C,0x49,0x53,0x54)  # RIFF AVI LIST
        'mov'  = [byte[]](0x00,0x00,0x00,0x14,0x66,0x74,0x79,0x70,0x71,0x74,0x20,0x20,0x00,0x00,0x00,0x00)  # ftyp qt
        'mp3'  = [byte[]](0x49,0x44,0x33,0x03,0x00,0x00,0x00,0x00,0x00,0x00,0x54,0x49,0x54,0x32)  # ID3v2
        
        # Professional
        'psd'  = [byte[]](0x38,0x42,0x50,0x53,0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00)  # 8BPS Photoshop
        'tif'  = [byte[]](0x49,0x49,0x2A,0x00,0x08,0x00,0x00,0x00,0x0E,0x00,0xFE,0x00,0x04,0x00,0x01,0x00)  # TIFF
        
        # Virtual Machines
        'vmdk' = [byte[]](0x4B,0x44,0x4D,0x56,0x01,0x00,0x00,0x00,0x03,0x00,0x00,0x00,0x00,0x00,0x00,0x00)  # KDMV VMware
        'vhd'  = [byte[]](0x63,0x6F,0x6E,0x65,0x63,0x74,0x69,0x78,0x00,0x00,0x00,0x02,0x00,0x00,0x00,0x00)  # conectix VHD
    }
    
    $fs = $null
    try {
        if ($WhatIf) {
            Write-Host "    WOULD CREATE: $FilePath ($Size bytes, $FileType)" -ForegroundColor Cyan
            return $true
        }
        
        # Get enhanced header for file type
        $header = if ($enhancedHeaders.ContainsKey($FileType)) { 
            $enhancedHeaders[$FileType] 
        } else { 
            [byte[]](0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77)  # Generic header
        }
        
        # Create file with enhanced header
        [System.IO.File]::WriteAllBytes($FilePath, $header)
        
        # Mark as sparse
        cmd /c "fsutil sparse setflag `"$FilePath`"" 2>$null | Out-Null
        
        # Set logical size
        $fs = [System.IO.File]::Open($FilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write)
        $fs.Seek($Size-1, [System.IO.SeekOrigin]::Begin) | Out-Null
        $fs.WriteByte(0)
        
        return $true
    } catch {
        Write-Host "    ✗ Failed to create file: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    } finally {
        if ($fs) {
            $fs.Close()
            $fs.Dispose()
        }
    }
}

function Get-RealisticFileSize {
    param([string]$FileType)
    
    # Realistic size ranges per file type (in bytes)
    $typeSizes = @{
        # Documents
        'docx' = @{Min=32KB; Max=2MB}
        'doc'  = @{Min=24KB; Max=1MB}
        'pdf'  = @{Min=100KB; Max=5MB}
        'txt'  = @{Min=1KB; Max=100KB}
        'rtf'  = @{Min=16KB; Max=500KB}
        
        # Spreadsheets
        'xlsx' = @{Min=64KB; Max=15MB}
        'xls'  = @{Min=48KB; Max=8MB}
        'csv'  = @{Min=2KB; Max=50MB}
        
        # Presentations
        'pptx' = @{Min=1MB; Max=100MB}
        'ppt'  = @{Min=512KB; Max=50MB}
        
        # Data
        'xml'  = @{Min=4KB; Max=10MB}
        'json' = @{Min=2KB; Max=5MB}
        
        # Images
        'jpg'  = @{Min=500KB; Max=12MB}
        'png'  = @{Min=100KB; Max=25MB}
        'gif'  = @{Min=50KB; Max=5MB}
        'bmp'  = @{Min=1MB; Max=50MB}
        'tif'  = @{Min=5MB; Max=200MB}
        'psd'  = @{Min=10MB; Max=1GB}
        
        # Email/Web
        'msg'  = @{Min=25KB; Max=20MB}
        'htm'  = @{Min=8KB; Max=2MB}
        'html' = @{Min=8KB; Max=2MB}
        
        # Archives
        'zip'  = @{Min=1MB; Max=500MB}
        '7z'   = @{Min=1MB; Max=500MB}
        
        # Media (Big Files)
        'mp4'  = @{Min=100MB; Max=4GB}
        'mkv'  = @{Min=500MB; Max=8GB}
        'avi'  = @{Min=200MB; Max=2GB}
        'mov'  = @{Min=100MB; Max=3GB}
        'mp3'  = @{Min=3MB; Max=15MB}
        'iso'  = @{Min=650MB; Max=8GB}
        
        # VM Files  
        'vmdk' = @{Min=1GB; Max=500GB}
        'vhd'  = @{Min=500MB; Max=100GB}
    }
    
    if ($typeSizes.ContainsKey($FileType)) {
        $range = $typeSizes[$FileType]
        return Get-Random -Minimum $range.Min -Maximum $range.Max
    } else {
        # Default range for unknown types
        return Get-Random -Minimum 64KB -Maximum 10MB
    }
}

function Set-FileTimestamps {
    param([string]$FilePath, [datetime]$StartDate, [datetime]$EndDate)
    
    try {
        if ($WhatIf) { return $true }
        
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

# === VALIDATION ===

Write-Host "Validating environment..." -ForegroundColor Yellow

if (-not (Test-Path $RootPath)) {
    Write-Host "✗ Root path $RootPath does not exist!" -ForegroundColor Red
    exit 1
}

$allFolders = Get-ChildItem $RootPath -Recurse -Directory -Force | Where-Object { 
    -not $_.Attributes.ToString().Contains("System") 
}

if ($allFolders.Count -eq 0) {
    Write-Host "✗ No folders found under $RootPath!" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Found $($allFolders.Count) folders for intelligent file placement" -ForegroundColor Green

$domainUsers = Get-RandomDomainUsers

# === ENHANCED FILE CREATION ===

Write-Host "`nCreating $FileCount intelligent files..." -ForegroundColor Yellow

# Enhanced filename prefixes by department
$businessPrefixes = @{
    'HR' = @('Employee','Handbook','Policy','Benefits','Onboarding','Review','Timesheet','Training','Payroll')
    'Finance' = @('Budget','Invoice','Statement','Report','Expense','Audit','Tax','Forecast','Analysis')
    'Engineering' = @('Spec','Design','Code','Test','Release','Bug','Feature','API','Database')
    'Marketing' = @('Campaign','Brand','Social','Event','Presentation','Asset','Analysis','Lead')
    'Sales' = @('Quote','Proposal','Contract','Lead','Territory','Forecast','Demo','Account')
    'Legal' = @('Contract','Agreement','Policy','Compliance','Case','Brief','NDA','IP')
    'IT' = @('Config','Backup','Log','Script','Install','Update','Security','Monitor')
    'Support' = @('Ticket','Issue','FAQ','Guide','Solution','Escalation','Knowledge','Help')
    'General' = @('Document','File','Data','Report','Meeting','Project','Archive','Temp')
}

$startTime = Get-Date
$createdCount = 0
$ownershipFailCount = 0
$fileFailCount = 0

# Statistics tracking
$departmentStats = @{}
$typeStats = @{}
$eraStats = @{}

for ($i = 1; $i -le $FileCount; $i++) {
    # Select random folder
    $folder = Get-Random -InputObject $allFolders
    $folderPath = $folder.FullName
    
    # Intelligent file type selection
    $department = Get-DepartmentFromPath -FolderPath $folderPath
    $fileDate = Get-RandomDate $StartDate $EndDate
    $era = Get-FileEra -FileDate $fileDate
    $isBigFile = (Get-Random -Minimum 1 -Maximum 100) -le 10  # 10% big files
    
    $fileType = Get-SmartFileType -Department $department -Era $era -IsBigFile $isBigFile
    $size = Get-RealisticFileSize -FileType $fileType
    
    # Smart filename generation
    $prefixList = if ($businessPrefixes.ContainsKey($department)) { 
        $businessPrefixes[$department] 
    } else { 
        $businessPrefixes['General'] 
    }
    
    $prefix = Get-Random -InputObject $prefixList
    $randCode = -join ((65..90)+(97..122)+(48..57) | Get-Random -Count 8 | ForEach-Object {[char]$_})
    $fileName = "$prefix-$randCode.$fileType"
    $fullPath = Join-Path $folderPath $fileName
    
    # Progress with intelligence stats
    if (($i % 250) -eq 1 -or $i -eq 1) {
        $elapsed = (Get-Date) - $startTime
        $rate = if ($elapsed.TotalSeconds -gt 0) { ($i-1) / $elapsed.TotalSeconds } else { 0 }
        $eta = if ($rate -gt 0) { [TimeSpan]::FromSeconds(($FileCount - $i) / $rate) } else { [TimeSpan]::Zero }
        
        Write-Host "[$i/$FileCount] $department/$era: $fileName ($([math]::Round($size/1MB,1))MB) ETA: $($eta.ToString('hh\:mm\:ss'))" -ForegroundColor Green
    }
    
    try {
        # Create intelligent sparse file
        $fileCreated = New-EnhancedSparseFile -FilePath $fullPath -FileType $fileType -Size $size
        
        if ($fileCreated) {
            # Set random domain user ownership
            if ($domainUsers.Count -gt 0) {
                $randomUser = Get-Random -InputObject $domainUsers
                $owner = "PLAB\$($randomUser.SamAccountName)"
            } else {
                $owner = $DomainOwner
            }
            
            $ownershipResult = Set-DomainOwnership -Path $fullPath -Owner $owner
            if (-not $ownershipResult) { $ownershipFailCount++ }
            
            # Set era-appropriate timestamps (ensure we don't exceed EndDate)
            $maxDate = if ($fileDate.AddDays(365) -gt $EndDate) { $EndDate } else { $fileDate.AddDays(365) }
            Set-FileTimestamps -FilePath $fullPath -StartDate $fileDate.AddDays(-30) -EndDate $maxDate | Out-Null
            
            # Update statistics
            $departmentStats[$department] = ($departmentStats[$department] ?? 0) + 1
            $typeStats[$fileType] = ($typeStats[$fileType] ?? 0) + 1
            $eraStats[$era] = ($eraStats[$era] ?? 0) + 1
            
            $createdCount++
        } else {
            $fileFailCount++
        }
        
    } catch {
        Write-Host "✗ ERROR creating $fullPath : $($_.Exception.Message)" -ForegroundColor Red
        $fileFailCount++
    }
}

# === ENHANCED SUMMARY REPORT ===

$endTime = Get-Date
$totalTime = $endTime - $startTime
$avgRate = if ($totalTime.TotalSeconds -gt 0) { $createdCount / $totalTime.TotalSeconds } else { 0 }

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "ENHANCED INTELLIGENT FILE CREATION COMPLETE" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Files requested: $FileCount" -ForegroundColor Green
Write-Host "Files created: $createdCount" -ForegroundColor Green
Write-Host "File failures: $fileFailCount" -ForegroundColor $(if($fileFailCount -gt 0){'Red'}else{'Green'})
Write-Host "Ownership failures: $ownershipFailCount" -ForegroundColor $(if($ownershipFailCount -gt 0){'Yellow'}else{'Green'})
Write-Host "Total time: $($totalTime.ToString('hh\:mm\:ss'))" -ForegroundColor Green
Write-Host "Average rate: $([math]::Round($avgRate,1)) files/second" -ForegroundColor Green

Write-Host "`n--- INTELLIGENCE STATISTICS ---" -ForegroundColor Yellow
Write-Host "Department Distribution:" -ForegroundColor Yellow
if ($createdCount -gt 0) {
    $departmentStats.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
        $pct = [math]::Round(($_.Value / $createdCount) * 100, 1)
        Write-Host "  $($_.Key): $($_.Value) files ($pct%)" -ForegroundColor White
    }
} else {
    Write-Host "  No files created" -ForegroundColor Red
}

Write-Host "`nFile Type Distribution (Top 10):" -ForegroundColor Yellow
if ($createdCount -gt 0) {
    $typeStats.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10 | ForEach-Object {
        $pct = [math]::Round(($_.Value / $createdCount) * 100, 1)
        Write-Host "  .$($_.Key): $($_.Value) files ($pct%)" -ForegroundColor White
    }
} else {
    Write-Host "  No files created" -ForegroundColor Red
}

Write-Host "`nEra Distribution:" -ForegroundColor Yellow
if ($createdCount -gt 0) {
    $eraStats.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
        $pct = [math]::Round(($_.Value / $createdCount) * 100, 1)
        Write-Host "  $($_.Key): $($_.Value) files ($pct%)" -ForegroundColor White
    }
} else {
    Write-Host "  No files created" -ForegroundColor Red
}

if ($WhatIf) {
    Write-Host "`nWhatIf mode completed - no actual files created" -ForegroundColor Cyan
} else {
    Write-Host "`n✓ ENHANCED REALISTIC FILES CREATED:" -ForegroundColor Green
    Write-Host "  ✓ Department-aware file types" -ForegroundColor Green
    Write-Host "  ✓ Era-appropriate technology" -ForegroundColor Green
    Write-Host "  ✓ Realistic file sizes per type" -ForegroundColor Green
    Write-Host "  ✓ Enhanced file headers" -ForegroundColor Green
    Write-Host "  ✓ Smart business-like filenames" -ForegroundColor Green
    Write-Host "  ✓ Random domain user ownership" -ForegroundColor Green
    Write-Host "  ✓ Temporal metadata evolution" -ForegroundColor Green
}

Write-Host "`nIntelligent enterprise file system ready for Symphony!" -ForegroundColor Green
