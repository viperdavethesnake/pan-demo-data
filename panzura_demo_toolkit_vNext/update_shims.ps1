# In PowerShell 7.x
Import-Module ActiveDirectory -SkipEditionCheck
Import-Module SmbShare        -SkipEditionCheck


# Your helper module (native PS7 is fine)
Import-Module .\set_privs.psm1
