# Resolve-DeptFromPath — given an absolute path and the share root, return
# the dept name whose folder owns this path, or $null if not a dept path
# (cross-dept, root, legacy, etc.). Case-insensitive match against config.
function Resolve-DeptFromPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ShareRoot,
        [Parameter(Mandatory)][array]$Departments
    )
    $normPath = $Path -replace '/','\'
    $normRoot = $ShareRoot.TrimEnd('\') + '\'
    if (-not $normPath.StartsWith($normRoot, [StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }
    $rel = $normPath.Substring($normRoot.Length)
    if (-not $rel) { return $null }
    $parts = $rel -split '\\'
    if ($parts.Count -lt 1) { return $null }
    $first = $parts[0]
    foreach ($d in $Departments) {
        if ($d.Name -ieq $first) { return $d.Name }
    }
    return $null
}

# Get-RelativeFolderPath — normalize a full path to forward-slash relative form.
function Get-RelativeFolderPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ShareRoot
    )
    $normPath = $Path -replace '\\','/'
    $normRoot = ($ShareRoot -replace '\\','/').TrimEnd('/') + '/'
    if (-not $normPath.StartsWith($normRoot, [StringComparison]::OrdinalIgnoreCase)) {
        return $normPath
    }
    return $normPath.Substring($normRoot.Length).TrimEnd('/')
}
