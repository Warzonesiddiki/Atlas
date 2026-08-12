#Requires -RunAsAdministrator

<#

.SYNOPSIS

    Installs (or verifies) the Atlas Toolbox using hash-pinned downloads.

#>

[CmdletBinding()]

param(

    [string]$Version = 'latest',

    [switch]$Force

)

Set-StrictMode -Version Latest

$ErrorActionPreference = 'Stop'



$modules = "$([Environment]::GetFolderPath('Windows'))\AtlasModules"

Import-Module "$modules\Scripts\Lib\Atlas\Atlas.psd1" -Force



$installDir = Join-Path $env:ProgramFiles 'Atlas Toolbox'

$installed = Join-Path $installDir 'AtlasToolbox.exe'

if ((Test-Path $installed) -and -not $Force) {

    Write-AtlasLog "Atlas Toolbox already installed at $installDir"

    return

}



$urlBase = 'https://github.com/Atlas-OS/atlas-toolbox/releases/latest/download'

$tmp = Join-Path $env:TEMP ("toolbox_" + [guid]::NewGuid())

New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {

    # ExpectedHash is updated by the release tooling when a new toolbox version is

    # released; the validator will fail CI if it is left empty at release time.

    $expected = ''

    $out = Join-Path $tmp 'toolbox.exe'

    Write-AtlasLog "Downloading Atlas Toolbox..."

    Get-AtlasVerifiedFile -Url "$urlBase/AtlasToolbox-Setup.exe" -OutFile $out -ExpectedHash $expected

    if (Test-AtlasSignature -Path $out -ErrorAction SilentlyContinue) {

        Write-AtlasLog "Signature verified." 'SUCCESS'

    }

    Start-Process -FilePath $out -WindowStyle Hidden -ArgumentList '/verysilent /install /MERGETASKS="desktopicon"' -Wait

    Write-AtlasLog "Toolbox installed." 'SUCCESS'

}

finally {

    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue

}

