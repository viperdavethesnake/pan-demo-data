# 1) Can we write *anything* to S:\Shared?
$probe = Join-Path 'S:\Shared' '__probe_can_write.tmp'
Remove-Item $probe -Force -ErrorAction SilentlyContinue
New-Item -ItemType File -Path $probe -Force -ErrorAction Stop
[IO.File]::WriteAllBytes($probe, [byte[]](1..16))
Get-Item $probe | Format-List FullName, Length, CreationTime, LastWriteTime

# 2) ACLs on S:\Shared (look for Modify/Write for your account or your groups)
(Get-Acl 'S:\Shared').Access | Format-Table IdentityReference, FileSystemRights, AccessControlType -AutoSize

# 3) If (1) failed because of permissions, reapply your share/filesystem ACLs:
.\set_share_acls.ps1
