# In PowerShell 7.x
Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop
Import-Module SmbShare        -SkipEditionCheck -ErrorAction Stop
Import-Module .\set_privs.psm1 -Force

# Your helper module (native PS7 is fine)
