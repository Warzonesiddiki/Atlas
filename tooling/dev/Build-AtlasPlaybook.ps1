<#

.SYNOPSIS

    Cross-platform wrapper around local-build.ps1. After building, regenerates

    the hash manifest and SBOM, then runs the validator. Works on Linux/macOS

    (delegates to pwsh) and Windows.

#>

[CmdletBinding()]

param(

    [string]$FileName = "Atlas Local",

    [switch]$NoPassword,

    [switch]$SkipValidation

)



Set-StrictMode -Version Latest

$ErrorActionPreference = 'Stop'



$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..' '..')

# Support both legacy (src/playbook) and new layout (playbook/)

$playbookRoot = if (Test-Path (Join-Path $repoRoot 'playbook')) { Join-Path $repoRoot 'playbook' } else { Join-Path $repoRoot 'src/playbook' }

$builder = Join-Path $repoRoot 'src/dependencies/local-build.ps1'



if (-not (Test-Path -LiteralPath $builder)) {

    # Also check new layout

    $builder = Join-Path $repoRoot 'dependencies/local-build.ps1'

}

if (-not (Test-Path -LiteralPath $builder)) {

    Write-Host "local-build.ps1 not found. Place it in src/dependencies/." -ForegroundColor Red

    exit 1

}



Push-Location $playbookRoot

try {

    $args = @('-AddLiveLog','-ReplaceOldPlaybook','-Removals','WinverRequirement,Verification',"-FileName",$FileName)

    if ($NoPassword) { $args += '-NoPassword' }

    & $builder @args

    if ($LASTEXITCODE -ne 0) { throw "local-build.ps1 failed with exit code $LASTEXITCODE" }

}

finally { Pop-Location }



# Regenerate manifests using the first existing script location

$hashScript = Join-Path $repoRoot 'tooling/ci/New-AtlasHashManifest.ps1'

$sbomScript = Join-Path $repoRoot 'tooling/ci/New-AtlasSBOM.ps1'

if (Test-Path $hashScript) { & $hashScript -PlaybookRoot $playbookRoot }

if (Test-Path $sbomScript) { & $sbomScript -PlaybookRoot $playbookRoot }



if (-not $SkipValidation) {

    $val = Join-Path $repoRoot 'tooling/ci/Validate-AtlasPlaybook.ps1'

    if (Test-Path $val) { & $val -PlaybookRoot $playbookRoot -Strict }

}



Write-Host "Build complete: $FileName.apbx" -ForegroundColor Green

