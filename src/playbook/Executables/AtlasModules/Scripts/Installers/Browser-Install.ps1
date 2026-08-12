#Requires -RunAsAdministrator

<#

.SYNOPSIS

    Installs a browser via the hash-pinned Get-AtlasVerifiedFile pipeline.

.PARAMETER Browser

    One of brave, firefox, librewolf, chrome.

#>

[CmdletBinding()]

param(

    [Parameter(Mandatory)][ValidateSet('brave','firefox','librewolf','chrome')][string]$Browser

)

Set-StrictMode -Version Latest

$ErrorActionPreference = 'Stop'



$modules = "$([Environment]::GetFolderPath('Windows'))\AtlasModules"

Import-Module "$modules\Scripts\Lib\Atlas\Atlas.psd1" -Force



$versions = Get-Content (Join-Path $PSScriptRoot 'versions.json') -Raw | ConvertFrom-Json

$entry = $versions.browsers.$Browser

if (-not $entry) { throw "Unknown browser: $Browser" }

if ([string]::IsNullOrWhiteSpace($entry.sha256)) {

    Write-AtlasLog ("No pinned hash for {0}; installing with signature verification only." -f $Browser) 'WARN'

}

$tmp = Join-Path $env:TEMP ("browser_{0}_{1}" -f $Browser, [guid]::NewGuid())

New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {

    $ext = if ($entry.url -match '\.msi$') { 'msi' } else { 'exe' }

    $out = Join-Path $tmp ("setup." + $ext)

    Get-AtlasVerifiedFile -Url $entry.url -OutFile $out -ExpectedHash $entry.sha256 -TimeoutSeconds 300

    if ($ext -eq 'msi') {

        Start-Process msiexec.exe -ArgumentList @('/i', ('"{0}"' -f $out), '/qn', '/norestart') -Wait

    }

    else {

        $silentArgs = switch ($Browser) {

            'chrome'   { '/silent', '/install' }

            'brave'    { '/silent', '/install' }

            'firefox'  { '/S' }

            'librewolf'{ '/S' }

        }

        Start-Process -FilePath $out -ArgumentList $silentArgs -Wait

    }

    Write-AtlasLog ("Browser {0} installed." -f $Browser) 'SUCCESS'

}

finally {

    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue

}

