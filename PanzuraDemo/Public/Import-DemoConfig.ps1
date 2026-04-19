function Import-DemoConfig {
<#
.SYNOPSIS
    Load and validate a PanzuraDemo configuration, with optional overlay.

.DESCRIPTION
    Loads config/default.psd1 (relative to the module), optionally merges an overlay
    psd1 (e.g., config/smoke.psd1) on top, loads the name corpora, validates the
    resulting hashtable, and returns it.

.PARAMETER Path
    Path to an overlay psd1 file. If omitted, only the default config is used.
    Accepts an absolute path, or a name like 'smoke' / 'default' which is resolved
    against the module's config/ folder.

.EXAMPLE
    Import-DemoConfig
    Import-DemoConfig -Path smoke
    Import-DemoConfig -Path C:/tmp/myconfig.psd1
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][string]$Path
    )

    $moduleConfigDir = Join-Path $script:ModuleRoot 'config'
    $base = Import-PowerShellDataFile -LiteralPath (Join-Path $moduleConfigDir 'default.psd1')

    if ($Path) {
        $resolved = $Path
        if (-not (Test-Path -LiteralPath $resolved)) {
            # Try as a bare name under config/
            $candidate = Join-Path $moduleConfigDir ("{0}.psd1" -f $Path)
            if (Test-Path -LiteralPath $candidate) { $resolved = $candidate }
            else { throw "Config file not found: '$Path' (tried '$candidate')." }
        }
        $overlay = Import-PowerShellDataFile -LiteralPath $resolved
        $merged = Merge-DemoConfigInternal -Base $base -Overlay $overlay
    } else {
        $merged = $base
    }

    # Attach name corpora at top level
    $merged.Names = Get-DemoConfigNames -NamesDir (Join-Path $moduleConfigDir 'names')

    # Attach module root for downstream use
    $merged.ModuleRoot = $script:ModuleRoot

    # Validate
    [void](Test-DemoConfigInternal -Config $merged)

    return $merged
}
