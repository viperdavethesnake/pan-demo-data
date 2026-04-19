# New-SparseFileInternal — create a sparse file of target size with a correct
# magic-byte header at offset 0 and one byte at offset (size-1). Implements
# the invariant per-file write ordering up to step 4 (file body). Later steps
# (attributes, ADS, ownership, timestamps) are the caller's responsibility
# because they must happen in a specific order across multiple subsystems.
function New-SparseFileInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][long]$SizeBytes,
        [Parameter(Mandatory)][byte[]]$HeaderBytes
    )
    if ($SizeBytes -lt 1) { $SizeBytes = 1 }
    # Ensure parent dir exists
    $dir = [IO.Path]::GetDirectoryName($Path)
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        [void][IO.Directory]::CreateDirectory($dir)
    }
    # Delete stale file so FileMode.Create is clean (avoid inheriting attrs)
    if (Test-Path -LiteralPath $Path) {
        [IO.File]::Delete($Path)
    }
    $fs = [IO.File]::Open($Path,
        [IO.FileMode]::Create,
        [IO.FileAccess]::Write,
        [IO.FileShare]::None)
    try {
        # 1. magic header
        $writeLen = [Math]::Min([long]$HeaderBytes.Length, $SizeBytes)
        if ($writeLen -gt 0) { $fs.Write($HeaderBytes, 0, [int]$writeLen) }
        # 2. mark sparse
        [PanzuraDemo.Native.Sparse]::SetSparse($fs.SafeFileHandle)
        # 3. seek to size-1 and write one byte to set file length
        if ($SizeBytes -gt 1) {
            [void]$fs.Seek($SizeBytes - 1, [IO.SeekOrigin]::Begin)
            $fs.WriteByte(0)
        }
        $fs.Flush()
    } finally {
        $fs.Close()
    }
}
