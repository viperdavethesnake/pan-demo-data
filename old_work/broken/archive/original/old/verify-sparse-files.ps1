param(
    [string]$RootPath = "S:\Shared",
    [int]$SampleSize = 1000,
    [int]$MinSparseRatio = 10 # logical size must be at least 10x physical size
)

function Get-PhysicalSize {
    param([string]$Path)
    $sig = @'
[DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
public static extern uint GetCompressedFileSizeW(string lpFileName, out uint lpFileSizeHigh);
'@
    $type = Add-Type -MemberDefinition $sig -Name 'Win32Utils' -Namespace 'Utils' -PassThru -ErrorAction SilentlyContinue
    $high = 0
    $low = $type::GetCompressedFileSizeW($Path, [ref]$high)
    if ($low -eq 0xFFFFFFFF) {
        $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        if ($err -ne 0) { return -1 }
    }
    return ([uint64]$high -shl 32) -bor $low
}

Write-Host "Scanning for files in $RootPath..."

$allFiles = Get-ChildItem $RootPath -Recurse -File -Force
if ($allFiles.Count -lt $SampleSize) {
    $SampleSize = $allFiles.Count
    Write-Host "Sample size reduced to $SampleSize (total files in tree)"
}
$sample = $allFiles | Get-Random -Count $SampleSize

$sparseCount = 0
$nonSparse = @()
$counter = 0

foreach ($file in $sample) {
    $counter++
    if ($counter % 100 -eq 0) {
        Write-Progress -Activity "Checking sparse files..." -Status "$counter / $SampleSize" -PercentComplete ($counter/$SampleSize*100)
    }

    $logical = $file.Length
    $physical = Get-PhysicalSize $file.FullName
    if ($physical -le 0) { continue }

    $sparseRatio = if ($physical -gt 0) { [math]::Round($logical / $physical, 2) } else { "inf" }

    if ($sparseRatio -eq "inf" -or $sparseRatio -ge $MinSparseRatio) {
        $sparseCount++
    } else {
        Write-Warning "$($file.FullName)`n  Logical: $logical  Physical: $physical  Ratio: $sparseRatio"
        $nonSparse += $file.FullName
    }
}

Write-Host ""
Write-Host "$sparseCount of $SampleSize files appear sparse (ratio >= $MinSparseRatio)"
Write-Host "$($nonSparse.Count) files failed the sparse check."

if ($nonSparse.Count -gt 0) {
    Write-Host "Sample failed files:"
    $nonSparse | Select-Object -First 10 | ForEach-Object { Write-Host " $_" }
}
