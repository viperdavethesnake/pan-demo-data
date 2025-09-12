param(
    [string]$RootPath = "S:\Shared",
    [long]$FileCount = 100000,
    [datetime]$StartDate = (Get-Date).AddYears(-10),
    [datetime]$EndDate = (Get-Date).AddYears(-5),
    [long]$MinNormalSize = 64KB,
    [long]$MaxNormalSize = 50MB,
    [long]$MinBigSize = 256MB,
    [long]$MaxBigSize = 4GB
)

function Get-RandomDate($start, $end) {
    $range = ($end - $start).TotalSeconds
    return $start.AddSeconds((Get-Random -Minimum 0 -Maximum $range))
}

$normalTypes = @{
    'docx' =  [byte[]](0x50,0x4B,0x03,0x04)
    'xlsx' =  [byte[]](0x50,0x4B,0x03,0x04)
    'pptx' =  [byte[]](0x50,0x4B,0x03,0x04)
    'pdf'  =  [byte[]](0x25,0x50,0x44,0x46)
    'txt'  =  [byte[]](0xEF,0xBB,0xBF)
    'csv'  =  [byte[]](0xEF,0xBB,0xBF)
    'xml'  =  [byte[]](0x3C,0x3F,0x78,0x6D,0x6C)
    'json' =  [byte[]](0x7B)
    'jpg'  =  [byte[]](0xFF,0xD8,0xFF)
    'png'  =  [byte[]](0x89,0x50,0x4E,0x47)
    'gif'  =  [byte[]](0x47,0x49,0x46,0x38)
    'bmp'  =  [byte[]](0x42,0x4D)
    'rtf'  =  [byte[]](0x7B,0x5C,0x72,0x74,0x66)
    'msg'  =  [byte[]](0xD0,0xCF,0x11,0xE0)
    'htm'  =  [byte[]](0x3C,0x21,0x44,0x4F,0x43)
    'html' =  [byte[]](0x3C,0x21,0x44,0x4F,0x43)
    'ppt'  =  [byte[]](0xD0,0xCF,0x11,0xE0)
    'xls'  =  [byte[]](0xD0,0xCF,0x11,0xE0)
    'doc'  =  [byte[]](0xD0,0xCF,0x11,0xE0)
    'zip'  =  [byte[]](0x50,0x4B,0x03,0x04)
    '7z'   =  [byte[]](0x37,0x7A,0xBC,0xAF,0x27,0x1C)
}
$bigTypes = @{
    'iso' =  [byte[]](0x43,0x44,0x30,0x30,0x31)
    'mp4' =  [byte[]](0x00,0x00,0x00,0x18,0x66,0x74,0x79,0x70)
    'mkv' =  [byte[]](0x1A,0x45,0xDF,0xA3)
    'avi' =  [byte[]](0x52,0x49,0x46,0x46)
    'mov' =  [byte[]](0x00,0x00,0x00,0x14,0x66,0x74,0x79,0x70)
    'mp3' =  [byte[]](0x49,0x44,0x33)
    'psd' =  [byte[]](0x38,0x42,0x50,0x53)
    'tif' =  [byte[]](0x49,0x49,0x2A,0x00)
}

Write-Host "Scanning folders..."
$allFolders = Get-ChildItem $RootPath -Recurse -Directory -Force | Where-Object { -not $_.Attributes.ToString().Contains("System") }
if ($allFolders.Count -eq 0) { throw "No folders found under $RootPath" }

Write-Host "Generating $FileCount files in $($allFolders.Count) folders..."

for ($i = 1; $i -le $FileCount; $i++) {
    $folder = Get-Random -InputObject $allFolders
    $subPath = $folder.FullName

    $extType = if ((Get-Random -Minimum 1 -Maximum 100) -le 10) { "big" } else { "normal" }
    if ($extType -eq "big") {
        $ext = (Get-Random -InputObject @($bigTypes.Keys + $null))
        $size = Get-Random -Minimum $MinBigSize -Maximum $MaxBigSize
        $header = if ($ext) { $bigTypes[$ext] } else { @(0x00,0x11,0x22,0x33) }
    } else {
        $ext = (Get-Random -InputObject @($normalTypes.Keys + $null))
        $size = Get-Random -Minimum $MinNormalSize -Maximum $MaxNormalSize
        $header = if ($ext) { $normalTypes[$ext] } else { @(0xAA,0xBB,0xCC,0xDD) }
    }

    $prefixes = @("QEmDN","xbKaovgt","SxWkuRnmQXEt","lfetCzvPAL","RDSqg","Doc","Team","Plan","Audit","Data","Backup","TEMP","Client","Project","Analysis","Report","Roster","Spec","Budget","Proposal","Memo")
    $randPrefix = Get-Random -InputObject $prefixes
    $randHex = -join ((65..90)+(97..122)+(48..57) | Get-Random -Count 8 | % {[char]$_})
    $fname = "$randPrefix-$randHex"
    if ($ext) { $fname += ".$ext" }
    $fullPath = Join-Path $subPath $fname

    if (($i % 100) -eq 1 -or $i -eq 1) {
        Write-Host "[$i/$FileCount] Creating: $fullPath ($size bytes, ext: $ext)"
    }

    try {
        # Create a sparse file
        [System.IO.File]::WriteAllBytes($fullPath, $header)
        # Mark as sparse using fsutil
        cmd /c "fsutil sparse setflag `"$fullPath`"" | Out-Null

        # Seek and write a byte at the end to set logical size
        $fs = [System.IO.File]::Open($fullPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write)
        $fs.Seek($size-1, [System.IO.SeekOrigin]::Begin) | Out-Null
        $fs.WriteByte(0)
        $fs.Close()

        # Set dates
        $created = Get-RandomDate $StartDate $EndDate
        $accessed = Get-RandomDate $created $EndDate
        $modified = Get-RandomDate $created $EndDate
        [System.IO.File]::SetCreationTime($fullPath, $created)
        [System.IO.File]::SetLastAccessTime($fullPath, $accessed)
        [System.IO.File]::SetLastWriteTime($fullPath, $modified)
    }
    catch {
        Write-Host ("ERROR on {0}: {1}" -f $fullPath, $_)
    }
}

Write-Host "DONE: $FileCount files created!"
