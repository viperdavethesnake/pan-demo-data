# Write-FileMagic — return the magic-byte header bytes for a given extension,
# plus a plain-text stub for extensions not in the binary magic table.
# Also handles text-header composition when the extension is text-like.
function Write-FileMagic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$Extension,
        [Parameter(Mandatory)][datetime]$CreationTime
    )
    $ext = $Extension.ToLower()
    if ($Config.FileHeaders.ContainsKey($ext)) {
        $ints = $Config.FileHeaders[$ext]
        $bytes = [byte[]]::new($ints.Count)
        for ($i = 0; $i -lt $ints.Count; $i++) { $bytes[$i] = [byte]$ints[$i] }
        return $bytes
    }
    # Text-type fallbacks
    $textStub = switch ($ext) {
        '.xml'  { "<?xml version=`"1.0`" encoding=`"UTF-8`"?>`r`n<root><created>$($CreationTime.ToString('o'))</created></root>" }
        '.json' { "{`"created`": `"$($CreationTime.ToString('o'))`", `"type`": `"enterprise_doc`"}" }
        '.html' { "<!DOCTYPE html>`r`n<html><head><title>Document</title></head><body></body></html>" }
        '.csv'  { "Date,User,Action,Status`r`n$($CreationTime.ToString('yyyy-MM-dd')),admin,created,success" }
        '.tsv'  { "Date`tUser`tAction`tStatus`r`n$($CreationTime.ToString('yyyy-MM-dd'))`tadmin`tcreated`tsuccess" }
        '.log'  { "$($CreationTime.ToString('yyyy-MM-dd HH:mm:ss')) INFO  Application started" }
        '.md'   { "# Document`r`nCreated $($CreationTime.ToString('o'))`r`n" }
        '.txt'  { "Document created $($CreationTime.ToString('yyyy-MM-dd HH:mm:ss'))" }
        '.yaml' { "created: $($CreationTime.ToString('o'))`r`ntype: enterprise_doc`r`n" }
        '.cfg'  { "[general]`r`ncreated=$($CreationTime.ToString('o'))`r`n" }
        '.ini'  { "[general]`r`ncreated=$($CreationTime.ToString('o'))`r`n" }
        '.ps1'  { "# PowerShell script`r`n# Created $($CreationTime.ToString('o'))`r`n" }
        '.psm1' { "# PowerShell module`r`n" }
        '.bat'  { "@echo off`r`nrem Created $($CreationTime.ToString('o'))`r`n" }
        '.cmd'  { "@echo off`r`nrem Created $($CreationTime.ToString('o'))`r`n" }
        '.vbs'  { "' VBScript`r`n' Created $($CreationTime.ToString('o'))`r`n" }
        '.sh'   { "#!/bin/bash`r`n# Created $($CreationTime.ToString('o'))`r`n" }
        '.py'   { "#!/usr/bin/env python3`r`n# Created $($CreationTime.ToString('o'))`r`n" }
        '.js'   { "// Created $($CreationTime.ToString('o'))`r`n" }
        '.ts'   { "// Created $($CreationTime.ToString('o'))`r`n" }
        '.cs'   { "// Created $($CreationTime.ToString('o'))`r`nnamespace Demo {}" }
        '.java' { "// Created $($CreationTime.ToString('o'))`r`n" }
        '.sql'  { "-- Created $($CreationTime.ToString('o'))`r`n" }
        '.tmp'  { "tmp" }
        '.bak'  { "BAK" }
        '.trn'  { "TRN" }
        default { "enterprise_doc created $($CreationTime.ToString('o'))" }
    }
    return [System.Text.Encoding]::UTF8.GetBytes($textStub)
}
