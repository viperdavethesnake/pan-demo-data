# Get-PersonName — pick a first + last from the corpus. Returns a record.
# New-PersonSamCandidate — turn a first/last into a SAM candidate with the
# standard 'first.last' format, lowercased, with fallback ladders when callers
# hit collisions (caller tracks the "used" set and asks for next candidates).
function Get-PersonName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$NameCorpora,   # @{ First=@(); Last=@() }
        [System.Random]$Rng = $null
    )
    if (-not $Rng) { $Rng = [System.Random]::new() }
    $first = $NameCorpora.First[$Rng.Next(0, $NameCorpora.First.Count)]
    $last  = $NameCorpora.Last[$Rng.Next(0, $NameCorpora.Last.Count)]
    [pscustomobject]@{
        First   = $first
        Last    = $last
        Display = "$first $last"
    }
}

# Reserve-UniqueSam — returns a SAM that isn't in -Used. Fills -Used on success.
# Collision ladder:
#   1. first.last
#   2. first.m.last  (random middle initial)
#   3. first.last2 / first.last3 / ...
#   4. f.last
function Reserve-UniqueSam {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$First,
        [Parameter(Mandatory)][string]$Last,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]]$Used,
        [System.Random]$Rng = $null
    )
    if (-not $Rng) { $Rng = [System.Random]::new() }
    $first = $First.ToLower() -replace '[^a-z]',''
    $last  = $Last.ToLower()  -replace '[^a-z]',''

    $candidates = New-Object System.Collections.Generic.List[string]
    $candidates.Add("$first.$last") | Out-Null
    # middle-initial variants (a..z, random order)
    $letters = 'abcdefghijklmnopqrstuvwxyz'.ToCharArray() | Sort-Object { $Rng.NextDouble() }
    foreach ($l in $letters[0..4]) { $candidates.Add("$first.$l.$last") | Out-Null }
    # numeric suffix
    for ($i = 2; $i -le 20; $i++) { $candidates.Add("$first.$last$i") | Out-Null }
    # initial + last
    $candidates.Add("$($first[0]).$last") | Out-Null
    for ($i = 2; $i -le 9; $i++) { $candidates.Add("$($first[0]).$last$i") | Out-Null }

    foreach ($c in $candidates) {
        # AD sAMAccountName limit is 20 chars
        if ($c.Length -gt 20) { continue }
        if (-not $Used.Contains($c)) {
            [void]$Used.Add($c)
            return $c
        }
    }
    # Pathological fallback: random 20-char noise
    while ($true) {
        $noise = "u" + ((1..12 | ForEach-Object { [char]([byte][char]'a' + $Rng.Next(0, 26)) }) -join '')
        if ($noise.Length -gt 20) { $noise = $noise.Substring(0, 20) }
        if (-not $Used.Contains($noise)) {
            [void]$Used.Add($noise)
            return $noise
        }
    }
}
