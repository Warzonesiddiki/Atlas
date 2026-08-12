#Requires -RunAsAdministrator

<#

.SYNOPSIS

    Restores Windows services (and, where backup data exists, other settings) to

    the pre-Atlas state captured at install time.



.DESCRIPTION

    During playbook install, services.yml backs up service configuration to

    %windir%\AtlasModules\Other\winServices.reg. This script imports that file

    and restores service start types to their Windows defaults. It is an

    incremental rollback (not a full uninstall); the full uninstall path is a

    Windows reinstall, as documented.

#>



[CmdletBinding()]

param(

    [switch]$NoPause,

    [switch]$Force

)



Set-StrictMode -Version Latest

$ErrorActionPreference = 'Continue'



Import-Module "$env:windir\AtlasModules\Scripts\Lib\Atlas\Atlas.psd1" -Force



$log = Start-AtlasLog -Name 'Rollback'



$windir = Get-AtlasWindowsDirectory

$backup = Join-Path $windir 'AtlasModules\Other\winServices.reg'



Write-AtlasLog "Atlas Services Restore" 'INFO'



if (-not (Test-Path -LiteralPath $backup)) {

    Write-AtlasLog "Backup file not found at $backup" 'ERROR'

    Write-AtlasLog "Cannot roll back services automatically. Use Windows System Restore or reset the OS." 'ERROR'

    Stop-AtlasLog | Out-Null

    if (-not $NoPause) { pause }

    exit 1

}



if (-not $Force) {

    Write-Host ""

    Write-Host "This will restore services to their pre-Atlas state (from $backup)." -ForegroundColor Yellow

    Write-Host "It does NOT remove Atlas files or re-install removed components; a reboot is required." -ForegroundColor Yellow

    $resp = Read-Host "Type YES to continue"

    if ($resp -ne 'YES') { Write-AtlasLog "Aborted by user."; exit 2 }

}



Invoke-AtlasSafe -Description 'Import service backup from winServices.reg' {

    $out = & reg.exe import $backup 2>&1

    foreach ($line in $out) { Write-AtlasLog $line 'DEBUG' }

    if ($LASTEXITCODE -ne 0) { throw "reg import failed with code $LASTEXITCODE" }

}



Write-AtlasLog "Service configuration restored. A reboot is required." 'SUCCESS'

$logPath = Stop-AtlasLog

Write-Host "Log saved to: $logPath" -ForegroundColor Cyan

if (-not $NoPause) { pause }

exit 0

