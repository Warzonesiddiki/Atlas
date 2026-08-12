<#

.SYNOPSIS

    Sets up a local development environment for hacking on Atlas.

    Installs PowerShell modules, linters, VS Code extensions, and a pre-commit

    hook. Safe to run multiple times (idempotent).



.DESCRIPTION

    Does NOT require admin for the PowerShell modules (installs to CurrentUser).

    VS Code extensions and npm-based linters (markdownlint, cspell) require

    admin only if your VS Code install is machine-wide.

#>

[CmdletBinding()]

param(

    [switch]$SkipVSCode,

    [switch]$Force

)



Set-StrictMode -Version Latest

$ErrorActionPreference = 'Stop'



$modules = @('Pester','PSScriptAnalyzer')

foreach ($m in $modules) {

    if (Get-Module -ListAvailable -Name $m) {

        Write-Host "  [ok] $m installed" -ForegroundColor Green

    }

    else {

        Write-Host "  [..] installing $m (CurrentUser)..." -ForegroundColor Yellow

        Install-Module -Name $m -Scope CurrentUser -Force -Repository PSGallery -AllowClobber

    }

}



if (-not $SkipVSCode -and (Get-Command code -ErrorAction SilentlyContinue)) {

    $exts = @(

        'ms-vscode.powershell',

        'redhat.vscode-yaml',

        'redhat.vscode-xml',

        'ionutvmi.reg',

        'foxundermoon.shell-format',

        'davidanson.vscode-markdownlint',

        'streetsidesoftware.code-spell-checker'

    )

    foreach ($e in $exts) {

        $installed = & code --list-extensions 2>$null | Where-Object { $_ -eq $e }

        if ($installed) { Write-Host "  [ok] VS Code extension $e" -ForegroundColor Green }

        else {

            Write-Host "  [..] installing VS Code extension $e..." -ForegroundColor Yellow

            & code --install-extension $e --force

        }

    }

}

else {

    Write-Host "  [--] VS Code not detected; skipping extensions." -ForegroundColor DarkGray

}



# Install python linters in a venv if Python is available

if (Get-Command python3 -ErrorAction SilentlyContinue) {

    $venv = Join-Path $PSScriptRoot '.venv'

    if (-not (Test-Path $venv)) {

        Write-Host "  [..] creating Python venv at $venv" -ForegroundColor Yellow

        python3 -m venv $venv

        & "$venv/bin/pip" install --quiet yamllint

    }

    Write-Host "  [ok] Python venv ready at $venv" -ForegroundColor Green

}



# Install pre-commit hooks (if pre-commit is present)

if (Get-Command pre-commit -ErrorAction SilentlyContinue) {

    Write-Host "  [..] installing pre-commit hooks" -ForegroundColor Yellow

    pre-commit install

}

else {

    Write-Host "  [--] pre-commit not installed; skipping hooks. Install with: pip install pre-commit" -ForegroundColor DarkGray

}



Write-Host ""

Write-Host "Development environment ready." -ForegroundColor Green

Write-Host "Quick commands:" -ForegroundColor Cyan

Write-Host "  pwsh tooling/dev/Build-AtlasPlaybook.ps1        # build APBX locally"

Write-Host "  pwsh tooling/ci/Validate-AtlasPlaybook.ps1       # run validator"

Write-Host "  pwsh -Command 'Invoke-Pester -Path tests'        # run unit tests"

Write-Host "  pwsh tooling/ci/New-AtlasHashManifest.ps1        # regenerate hash manifest"

Write-Host "  pwsh tooling/ci/New-AtlasSBOM.ps1                # regenerate SBOM"

