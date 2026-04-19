# Add-BulkGroupMember — bulk-add a set of users to a group in one call
# per group, catching ADIdentityAlreadyExists for idempotency.
# vNext2 used Get-ADGroupMember -Recursive per user (O(N^2)); this is O(N).
function Add-BulkGroupMember {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$GroupSam,
        [Parameter(Mandatory)][string[]]$UserSams
    )
    if (-not $UserSams -or $UserSams.Count -eq 0) { return }
    $group = $null
    try { $group = Get-ADGroup -Identity $GroupSam -ErrorAction Stop } catch {
        Write-Warning "Add-BulkGroupMember: group '$GroupSam' not found."
        return
    }
    # Chunk to avoid very large single calls
    $chunkSize = 500
    for ($i = 0; $i -lt $UserSams.Count; $i += $chunkSize) {
        $slice = $UserSams[$i..([Math]::Min($i + $chunkSize - 1, $UserSams.Count - 1))]
        try {
            Add-ADGroupMember -Identity $group -Members $slice -ErrorAction Stop
        } catch {
            # Fall back to per-user add so one duplicate doesn't kill the batch
            foreach ($u in $slice) {
                try { Add-ADGroupMember -Identity $group -Members $u -ErrorAction Stop }
                catch {
                    if ($_.Exception.Message -notmatch 'already a member|already exists') {
                        Write-Verbose "Failed to add $u to $GroupSam : $($_.Exception.Message)"
                    }
                }
            }
        }
    }
}
