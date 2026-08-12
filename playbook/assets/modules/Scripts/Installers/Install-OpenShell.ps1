#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Hash-pinned installer for Open-Shell (replaces the curl+winget-based
    "Install Open-Shell.cmd"). Uses Get-AtlasVerifiedFile for integrity.
#>
[CmdletBinding()]
param(
    [string]$VersionsJson = "$([Environment]::GetFolderPath('Windows'))\AtlasModules\Scripts\Installers\versions.json"
)

$ErrorActionPreference = 'Stop'
$windir = [Environment]::GetFolderPath('Windows')
Import-Module "$windir\AtlasModules\Scripts\Lib\Atlas\Atlas.psd1" -Force
. "$windir\AtlasModules\Scripts\Security\Get-AtlasVerifiedFile.ps1"

if (-not (Test-Path $VersionsJson)) {
    $VersionsJson = Join-Path $PSScriptRoot 'versions.json'
}
$v = Get-Content $VersionsJson -Raw | ConvertFrom-Json
$os = $v.openshell
if (-not $os -or -not $os.url) {
    throw "Open-Shell entry missing in versions.json."
}
if (-not $os.sha256) {
    Write-AtlasLog "Open-Shell SHA256 not pinned in versions.json; refusing to download." 'ERROR'
    throw "Refusing to install Open-Shell: sha256 not pinned. Run Bump-Versions.ps1 to populate hashes."
}

$tmp = Join-Path $env:TEMP ("atlas_os_" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    $installer = Join-Path $tmp 'OpenShellSetup.exe'
    Write-AtlasLog "Downloading Open-Shell from $($os.url)"
    Get-AtlasVerifiedFile -Url $os.url -OutFile $installer -ExpectedHash $os.sha256 -TimeoutSeconds 120
    Write-AtlasLog 'Installing Open-Shell (Start menu component only)...'
    $p = Start-Process -FilePath $installer -ArgumentList '/qn ADDLOCAL=StartMenu' -Wait -PassThru
    if ($p.ExitCode -ne 0) {
        throw "Open-Shell installer exited with code $($p.ExitCode)."
    }

    if ($os.skinUrl -and $os.skinSha256) {
        $skins = Join-Path ${env:ProgramFiles(x86)} 'Open-Shell\Skins'
        if (Test-Path $skins) {
            $skinZip = Join-Path $tmp 'FluentMetro.zip'
            try {
                Get-AtlasVerifiedFile -Url $os.skinUrl -OutFile $skinZip -ExpectedHash $os.skinSha256 -TimeoutSeconds 60
                Expand-Archive -Path $skinZip -DestinationPath $skins -Force
            } catch {
                Write-AtlasLog "Fluent-Metro skin install failed (non-fatal): $($_.Exception.Message)" 'WARN'
            }
        }
    }

    Write-AtlasLog 'Open-Shell installed.' 'SUCCESS'
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Process explorer
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
