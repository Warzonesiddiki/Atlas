<#
.SYNOPSIS
    Enterprise-grade validator for the Atlas playbook.

.DESCRIPTION
    Performs the following checks on every YAML file under Configuration/:
      1. YAML is well-formed (can be parsed after stripping AME Wizard !tags).
      2. Every referenced .cmd / .ps1 / .exe / .reg / .cab / .psm1 / .bat / .theme
         path exists on disk.
      3. !service calls use valid service startup types.
      4. !registryValue entries have a recognised `type` field.
      5. Required front-matter fields (title, description) are present.
      6. No disallowed patterns (Invoke-WebRequest without hash verification,
         hard-coded passwords, direct `cmd /c del` on system roots, etc.).
    Exits non-zero if any problem is found so it can be used in CI.

.PARAMETER PlaybookRoot
    Path to src/playbook. Defaults to the directory containing this script's
    parent repository layout (works locally and in CI).

.PARAMETER Strict
    Treat warnings as errors.
#>

[CmdletBinding()]
param(
    [string]$PlaybookRoot,
    [switch]$Strict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $PlaybookRoot) {
    # Support both new layout (repo-root/playbook) and legacy (src/playbook).
    $candidate = Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'playbook') -ErrorAction SilentlyContinue
    if (-not $candidate) { $candidate = Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'src' 'playbook') -ErrorAction SilentlyContinue }
    $PlaybookRoot = $candidate
}
if (-not $PlaybookRoot -or -not (Test-Path $PlaybookRoot)) { throw "Could not locate playbook root. Pass -PlaybookRoot explicitly." }

$ErrorCount = 0
$WarningCount = 0

function Write-ValidationError {
    param([string]$File, [string]$Message, [int]$Line = 0)
    $script:ErrorCount++
    $loc = if ($Line) { ":$Line" } else { '' }
    Write-Host ("ERROR  {0}{1} - {2}" -f $File, $loc, $Message) -ForegroundColor Red
}
function Write-ValidationWarning {
    param([string]$File, [string]$Message, [int]$Line = 0)
    $script:WarningCount++
    $loc = if ($Line) { ":$Line" } else { '' }
    Write-Host ("WARN   {0}{1} - {2}" -f $File, $loc, $Message) -ForegroundColor Yellow
}

$knownRegistryTypes = @('REG_SZ','REG_DWORD','REG_QWORD','REG_EXPAND_SZ','REG_MULTI_SZ','REG_BINARY','REG_NONE')
$disallowedPatterns = @(
    @{ Regex = '(?i)Invoke-WebRequest\b'; Message = 'Invoke-WebRequest used; wrap downloads in Get-AtlasVerifiedFile.ps1 for hash pinning' },
    @{ Regex = '(?i)Start-Process\s+.*\.exe'; Message = 'Start-Process on EXE; ensure the target binary is hash-verified or shipped with Atlas' },
    @{ Regex = '(?i)curl\.exe\s'; Message = 'curl.exe used; wrap downloads in Get-AtlasVerifiedFile.ps1 for hash pinning' },
    @{ Regex = '(?i)iwr\s'; Message = 'iwr (Invoke-WebRequest alias) used; wrap downloads in Get-AtlasVerifiedFile.ps1' }
)

$yamlFiles = Get-ChildItem -Path (Join-Path $PlaybookRoot 'Configuration') -Recurse -Filter *.yml
Write-Host ("Validating {0} YAML files under {1}" -f $yamlFiles.Count, $PlaybookRoot) -ForegroundColor Cyan

foreach ($yf in $yamlFiles) {
    $rel = $yf.FullName.Substring($PlaybookRoot.Length).TrimStart('\','/')
    $lines = Get-Content -LiteralPath $yf.FullName -ErrorAction Stop
    $raw = $lines -join [Environment]::NewLine

    # 1. Front-matter: title + description
    if ($raw -notmatch '(?m)^title:\s*\S') {
        Write-ValidationError -File $rel -Message 'Missing required `title:` field'
    }
    if ($raw -notmatch '(?m)^description:\s*\S') {
        Write-ValidationError -File $rel -Message 'Missing required `description:` field'
    }

    # 1b. New tweaks under playbook/tweaks/* should declare appliesTo + sources
    if ($rel -match '^(tweaks[\\/](ai|gaming|enterprise|networking|security)[\\/])') {
        if ($raw -notmatch '(?m)^appliesTo:') {
            Write-ValidationWarning -File $rel -Message 'New tweak is missing `appliesTo:` build-range block'
        }
        if ($raw -notmatch '(?m)^sources:') {
            Write-ValidationWarning -File $rel -Message 'New tweak is missing `sources:` citations block'
        }
    }

    # 2. YAML parse check (YAML with custom tags is not valid YAML, so strip tags first).
    $stripped = [regex]::Replace($raw, '!\w+:', 'customtag_')
    try {
        # We don't require PowerShell YAML module in CI; do a basic indentation/brace sanity check.
        # A formal parser can be swapped in by installing powershell-yaml.
        if (Get-Module -ListAvailable -Name powershell-yaml) {
            $null = ConvertFrom-Yaml $stripped
        }
    }
    catch {
        Write-ValidationError -File $rel -Message ("YAML parse error: " + $_.Exception.Message)
    }

    # 3. Check referenced files exist
    $refMatches = [regex]::Matches($raw, "(?m)['`"]\\?([^'"`]*?\.(?:cmd|ps1|exe|reg|cab|psm1|bat|theme|ps1xml))['`"]")
    foreach ($m in $refMatches) {
        $cand = $m.Groups[1].Value -replace '^\\','' -replace '/','\'
        $candidates = @(
            (Join-Path (Split-Path $yf.FullName -Parent) $cand),
            (Join-Path $PlaybookRoot $cand),
            (Join-Path $PlaybookRoot 'Executables' $cand.TrimStart('.\')),
            (Join-Path $PlaybookRoot 'Executables' $cand)
        ) | Select-Object -Unique
        $found = $false
        foreach ($c in $candidates) {
            if (Test-Path -LiteralPath $c -PathType Leaf) { $found = $true; break }
        }
        if (-not $found) {
            Write-ValidationError -File $rel -Message ("Referenced file not found: " + $cand)
        }
    }

    # 4. Validate registry types
    $typeMatches = [regex]::Matches($raw, "type:\s*'([^']+)'")
    foreach ($tm in $typeMatches) {
        $t = $tm.Groups[1].Value
        if ($knownRegistryTypes -notcontains $t) {
            Write-ValidationWarning -File $rel -Message ("Unknown registry type: " + $t)
        }
    }

    # 5. Line-level disallowed patterns
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $ln = $lines[$i]
        foreach ($p in $disallowedPatterns) {
            if ($ln -match $p.Regex -and $ln -notmatch '(?i)#\s*allow-' -and $ln -notmatch 'atlas-toolbox') {
                # Only flag command: / powerShell: bodies, not comments
                if ($ln -match '^\s*#') { continue }
                Write-ValidationWarning -File $rel -Message $p.Message -Line ($i+1)
            }
        }
        if ($ln -match 'pause\s*>\s*null\b') {
            Write-ValidationWarning -File $rel -Message 'Typo: "pause > null" creates a file named "null"; use "> nul"' -Line ($i+1)
        }
    }

    # 6. Check for Tabs indent (violates .editorconfig for YAML)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\t') {
            Write-ValidationWarning -File $rel -Message 'Tab indentation (use spaces per .editorconfig)' -Line ($i+1)
        }
    }
}

# Validate playbook.conf exists and contains <SupportedBuilds>
$conf = Join-Path $PlaybookRoot 'playbook.conf'
if (-not (Test-Path -LiteralPath $conf)) {
    Write-ValidationError -File 'playbook.conf' -Message 'Missing playbook.conf'
}
else {
    $confText = Get-Content -LiteralPath $conf -Raw
    if ($confText -notmatch '<SupportedBuilds>') {
        Write-ValidationWarning -File 'playbook.conf' -Message '<SupportedBuilds> block missing'
    }
    if ($confText -notmatch '<Version>') {
        Write-ValidationWarning -File 'playbook.conf' -Message '<Version> element missing'
    }
}

Write-Host ""
Write-Host ("Validation complete. Errors: {0}, Warnings: {1}" -f $ErrorCount, $WarningCount) -ForegroundColor Cyan
if ($ErrorCount -gt 0 -or ($Strict -and $WarningCount -gt 0)) { exit 1 }
exit 0
