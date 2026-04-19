# Get-FileName — pick a name template for the given folder path, substitute
# tokens, and return the final file name. Extension is appended if the template
# doesn't already supply one.
#
# Templates live in $Config.NameTemplates, keyed by glob-style patterns like
# 'Finance/AP/*'. Matching is done against the relative folder path under
# the share root, using the first matching pattern in insertion order.
# Fallback template is $Config.NameTemplates.default.
#
# Supported tokens (case-insensitive):
#   {year}     — a 4-digit year near the file's CreationTime (or current year if unknown)
#   {month}    — 2-digit month
#   {quarter}  — 1..4
#   {date}     — YYYYMMDD
#   {num}      — 3-5 digit random
#   {n}        — 1-2 digit random
#   {hash}     — 8-char hex random
#   {ext}      — extension including dot (e.g. .pdf)
#   {prefix}   — dept/subfolder-derived base word
#   {dept}     — department name
#   {version}  — semver-ish like 1.2.3
#   {Vendor}/{Client}/{Project}/{Product}/{Customer}/{Matter}/{Topic}
#               — sampled from DataPools
#   {module}/{name}/{feature}/{component}/{campaign}/{user}/{event}/{variant}
#   {building}/{room}/{target}/{task}/{subject}/{title}
#               — sampled ad-hoc from DataPools.Topics or generated
function Get-FileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$RelFolderPath,      # e.g., "Finance/AP"
        [Parameter(Mandatory)][string]$Extension,          # e.g., ".xlsx"
        [Parameter(Mandatory)][datetime]$CreationTime,
        [Parameter(Mandatory)][string]$Department,
        [System.Random]$Rng = $null
    )
    if (-not $Rng) { $Rng = [System.Random]::new() }
    $templates = $Config.NameTemplates

    # Find matching pattern
    $match = $null
    foreach ($pattern in $templates.Keys) {
        if ($pattern -eq 'default') { continue }
        if (Test-FolderPatternMatch -Pattern $pattern -Path $RelFolderPath) {
            $match = $templates[$pattern]
            break
        }
    }
    if (-not $match) { $match = $templates['default'] }

    $template = $match[$Rng.Next(0, $match.Count)]

    $name = Expand-FileNameTokens -Template $template -Config $Config -CreationTime $CreationTime `
        -Department $Department -Extension $Extension -RelFolderPath $RelFolderPath -Rng $Rng

    # Ensure extension
    if (-not [IO.Path]::HasExtension($name)) {
        $name = $name + $Extension
    }
    return Sanitize-FileName $name
}

function Test-FolderPatternMatch {
    [CmdletBinding()]
    param([string]$Pattern, [string]$Path)
    $p = $Path -replace '\\','/'
    $pat = $Pattern -replace '\\','/'
    if ($p.EndsWith('/')) { $p = $p.TrimEnd('/') }
    if ($p -like $pat) { return $true }
    # 'X/*' should also match the folder 'X' itself (covers file-in-folder cases).
    if ($pat.EndsWith('/*')) {
        $trimmed = $pat.Substring(0, $pat.Length - 2)
        if ($p -like $trimmed) { return $true }
    }
    return $false
}

function Sanitize-FileName {
    param([string]$Name)
    # strip characters invalid in NTFS filenames (but keep spaces/parens)
    $invalid = [IO.Path]::GetInvalidFileNameChars()
    $sb = [System.Text.StringBuilder]::new($Name.Length)
    foreach ($c in $Name.ToCharArray()) {
        if ($invalid -contains $c) { [void]$sb.Append('_') }
        else { [void]$sb.Append($c) }
    }
    $out = $sb.ToString().Trim()
    if ([string]::IsNullOrWhiteSpace($out)) { $out = "file" }
    return $out
}

function Expand-FileNameTokens {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Template,
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][datetime]$CreationTime,
        [Parameter(Mandatory)][string]$Department,
        [Parameter(Mandatory)][string]$Extension,
        [Parameter(Mandatory)][string]$RelFolderPath,
        [Parameter(Mandatory)][System.Random]$Rng
    )
    $pools   = $Config.DataPools
    $result  = $Template

    $token = [regex]'\{([^}]+)\}'
    while (($m = $token.Match($result)).Success) {
        $key = $m.Groups[1].Value
        $value = switch -Regex ($key) {
            '^year$'      { '{0:D4}' -f $CreationTime.Year }
            '^month$'     { '{0:D2}' -f $CreationTime.Month }
            '^quarter$'   { [string](1 + [math]::Floor(($CreationTime.Month - 1) / 3)) }
            '^date$'      { $CreationTime.ToString('yyyyMMdd') }
            '^num$'       { '{0:D5}' -f $Rng.Next(1, 99999) }
            '^n$'         { [string]$Rng.Next(1, 20) }
            '^hash$'      { ('{0:x8}' -f $Rng.Next([int]::MinValue, [int]::MaxValue)).Substring(0,8) }
            '^ext$'       { $Extension }
            '^dept$'      { $Department }
            '^version$'   { '{0}.{1}.{2}' -f $Rng.Next(1,6), $Rng.Next(0,12), $Rng.Next(0,99) }
            '^Vendor$'    { $pools.Vendors[$Rng.Next(0,$pools.Vendors.Count)] }
            '^Client$'    { $pools.Clients[$Rng.Next(0,$pools.Clients.Count)] }
            '^Project$'   { $pools.Projects[$Rng.Next(0,$pools.Projects.Count)] }
            '^Product$'   { $pools.Products[$Rng.Next(0,$pools.Products.Count)] }
            '^Customer$'  { $pools.Customers[$Rng.Next(0,$pools.Customers.Count)] }
            '^Matter$'    { $pools.Matters[$Rng.Next(0,$pools.Matters.Count)] }
            '^Topic$'     { $pools.Topics[$Rng.Next(0,$pools.Topics.Count)] }
            '^Campaign$'  { "Campaign_{0}" -f $Rng.Next(100,999) }
            '^Feature$'   { $pools.Topics[$Rng.Next(0,$pools.Topics.Count)] }
            '^Component$' { $pools.Topics[$Rng.Next(0,$pools.Topics.Count)] }
            '^module$'    { ('Module_{0}' -f $Rng.Next(1,50)) }
            '^Building$'  { "Building_{0}" -f [char](65 + $Rng.Next(0, 8)) }
            '^Room$'      { "Room_{0:D3}" -f $Rng.Next(100,600) }
            '^target$'    { $pools.Products[$Rng.Next(0,$pools.Products.Count)] }
            '^task$'      { $pools.Topics[$Rng.Next(0,$pools.Topics.Count)] }
            '^event$'     { "Event_{0}" -f $Rng.Next(1,50) }
            '^user$'      { "user_{0}" -f $Rng.Next(1,200) }
            '^variant$'   { @('primary','mono','dark','light','horizontal','vertical')[$Rng.Next(0,6)] }
            '^name$'      { "file_{0}" -f $Rng.Next(1,999) }
            '^Subject$'   { $pools.Topics[$Rng.Next(0,$pools.Topics.Count)] }
            '^title$'     { $pools.Topics[$Rng.Next(0,$pools.Topics.Count)] }
            '^prefix$'    {
                # derive from last folder segment
                $parts = $RelFolderPath -replace '\\','/' -split '/'
                $seg = $parts[-1]
                if (-not $seg) { $seg = $Department }
                $seg
            }
            default       { $key }  # leave unknown tokens literal
        }
        # splice in
        $result = $result.Substring(0, $m.Index) + $value + $result.Substring($m.Index + $m.Length)
    }
    return $result
}
