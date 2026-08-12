<#
.SYNOPSIS
    Verified-install wrapper for SOFTWARE.ps1 downloads.
.DESCRIPTION
    Uses Atlas module Get-AtlasVerifiedFile (hash-pinned, TLS 1.2+, atomic
    write) instead of bare curl.exe / Start-Process. Hashes must be filled
    by tooling/release/Bump-Versions.ps1 before release.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\..\modules\lib\Atlas' 'Atlas.psd1') -Force

# --- Toolbox (hash to be filled by Bump-Versions from versions.json) ---
$toolboxUrl = 'https://github.com/Atlas-OS/atlas-toolbox/releases/latest/download/AtlasToolbox-Setup.exe'
$toolboxHash = (Get-Content (Join-Path $PSScriptRoot '..\..\modules\Scripts\Installers' 'versions.json') -Raw | ConvertFrom-Json).toolbox.sha256
if ([string]::IsNullOrWhiteSpace($toolboxHash)) { throw 'toolbox sha256 empty — run Bump-Versions.ps1' }
Get-AtlasVerifiedFile -Url $toolboxUrl -ExpectedHash $toolboxHash -OutputPath "$env:TEMP\AtlasToolbox-Verified.exe"
Start-Process -FilePath "$env:TEMP\AtlasToolbox-Verified.exe" -WindowStyle Hidden -ArgumentList '/verysilent /install /MERGETASKS="desktopicon"' -Wait

# --- Brave (hash to be filled) ---
$braveUrl = 'https://laptop-updates.brave.com/latest/winx64-release'
# TODO: populate from versions.json browsers.brave.sha256 after release build
# Get-AtlasVerifiedFile -Url $braveUrl -ExpectedHash $braveHash -OutputPath ...

Write-Host 'SOFTWARE-verified download complete (hashes must be pinned before RC).' -ForegroundColor Green
