# PanzuraDemo.psm1 — root loader for the PanzuraDemo module.
# Responsibilities:
#   1. Compile native C# helpers (sparse + privilege) once per process.
#   2. Enable SeRestore / SeTakeOwnership once per process.
#   3. Dot-source every Private/ and Public/ script file.
#   4. Export Public/ functions via the manifest.

$ErrorActionPreference = 'Stop'
# Strict mode 1.0 disallows references to uninitialized variables but still
# permits $ht.MissingKey (returns $null) and $null.Property (returns $null).
# v3 was too aggressive for this data-heavy codebase.
Set-StrictMode -Version 1.0

$script:ModuleRoot = $PSScriptRoot

# --- Native type compilation (sparse + privilege) ---------------------------

$sparseSrc    = Get-Content -LiteralPath (Join-Path $ModuleRoot 'Private/Native/Sparse.cs')    -Raw
$privilegeSrc = Get-Content -LiteralPath (Join-Path $ModuleRoot 'Private/Native/Privilege.cs') -Raw
$securitySrc  = Get-Content -LiteralPath (Join-Path $ModuleRoot 'Private/Native/Security.cs')  -Raw

if (-not ('PanzuraDemo.Native.Sparse' -as [type])) {
    Add-Type -TypeDefinition $sparseSrc -Language CSharp -ErrorAction Stop | Out-Null
}
if (-not ('PanzuraDemo.Native.Privilege' -as [type])) {
    Add-Type -TypeDefinition $privilegeSrc -Language CSharp -ErrorAction Stop | Out-Null
}
if (-not ('PanzuraDemo.Native.SecurityNative' -as [type])) {
    Add-Type -TypeDefinition $securitySrc -Language CSharp -ErrorAction Stop | Out-Null
}

# Enable token privileges once for the process. Non-fatal if they fail —
# ownership operations will throw visibly later if they're genuinely needed.
[void][PanzuraDemo.Native.Privilege]::EnablePrivilege('SeRestorePrivilege')
[void][PanzuraDemo.Native.Privilege]::EnablePrivilege('SeTakeOwnershipPrivilege')
[void][PanzuraDemo.Native.Privilege]::EnablePrivilege('SeBackupPrivilege')

# --- Dot-source Private/ then Public/ ---------------------------------------

$privateFiles = Get-ChildItem -Path (Join-Path $ModuleRoot 'Private') -Filter *.ps1 -Recurse -File
foreach ($f in $privateFiles) { . $f.FullName }

$publicFiles = Get-ChildItem -Path (Join-Path $ModuleRoot 'Public') -Filter *.ps1 -File
foreach ($f in $publicFiles) { . $f.FullName }

Export-ModuleMember -Function ($publicFiles | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_.Name) })
