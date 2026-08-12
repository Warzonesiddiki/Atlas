# Atlas PowerShell Module - core implementation
# Licensed under GPL-3.0-only.
#
# This module is the single shared library for all Atlas scripts. It deliberately
# avoids exotic PS7-only features so it runs on Windows PowerShell 5.1 (which is
# what ships with Windows 11). Functions are pure where possible and always
# surface errors via exceptions rather than silent failures.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# Well-known paths (resolved once at import time)
# -----------------------------------------------------------------------------

function Get-AtlasWindowsDirectory {
    [CmdletBinding()]
    param()
    [Environment]::GetFolderPath('Windows')
}

function Get-AtlasModulesDirectory {
    [CmdletBinding()]
    param()
    Join-Path (Get-AtlasWindowsDirectory) 'AtlasModules'
}

function Get-AtlasDesktopDirectory {
    [CmdletBinding()]
    param()
    Join-Path (Get-AtlasWindowsDirectory) 'AtlasDesktop'
}

function Get-AtlasLogDirectory {
    [CmdletBinding()]
    param()
    $logDir = Join-Path (Get-AtlasModulesDirectory) 'Logs'
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    $logDir
}

# -----------------------------------------------------------------------------
# Privilege / identity helpers
# -----------------------------------------------------------------------------

function Test-AtlasAdmin {
    [CmdletBinding()]
    param()
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-AtlasTrustedInstaller {
    [CmdletBinding()]
    param()
    try {
        $current = [Security.Principal.WindowsIdentity]::GetCurrent()
        $current.User.Value -eq 'S-1-5-18' -and (Get-Process -Id $PID -ErrorAction SilentlyContinue).Path -like '*TrustedInstaller*'
    }
    catch { $false }
}

function Get-AtlasSystemArchitecture {
    [CmdletBinding()]
    param()
    # Returns 'arm64' or 'amd64' for the running OS. We avoid $env:PROCESSOR_ARCHITECTURE
    # because that can report the emulator (x86) on ARM under WOW64.
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    if ($cs.SystemType -match 'ARM64' -or ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64')) {
        'arm64'
    }
    else {
        'amd64'
    }
}

# -----------------------------------------------------------------------------
# Structured logging
# -----------------------------------------------------------------------------

$script:AtlasLogContext = @{
    FilePath = $null
    Started  = $null
}

function Start-AtlasLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $safeName = ($Name -replace '[^\w\-\.]', '_')
    $file = Join-Path (Get-AtlasLogDirectory) "$safeName`_$stamp.log"
    $script:AtlasLogContext.FilePath = $file
    $script:AtlasLogContext.Started  = Get-Date
    $header = @(
        '==========================================',
        "Atlas Log: $Name",
        "Started  : $($script:AtlasLogContext.Started.ToString('o'))",
        "User     : $([Security.Principal.WindowsIdentity]::GetCurrent().Name)",
        "IsAdmin  : $(Test-AtlasAdmin)",
        "IsTI     : $(Test-AtlasTrustedInstaller)",
        "Arch     : $(Get-AtlasSystemArchitecture)",
        "Build    : $((Get-CimInstance Win32_OperatingSystem).BuildNumber)",
        "PS Ver   : $($PSVersionTable.PSVersion)",
        "Path     : $file",
        '=========================================='
    ) -join [Environment]::NewLine
    $header | Out-File -FilePath $file -Encoding utf8
    $file
}

function Write-AtlasLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )
    $line = "[{0}] [{1,-5}] {2}" -f (Get-Date -Format 'HH:mm:ss.fff'), $Level, $Message
    Write-Host $line
    if ($script:AtlasLogContext.FilePath) {
        try { $line | Out-File -FilePath $script:AtlasLogContext.FilePath -Append -Encoding utf8 }
        catch { Write-Warning "Failed to write to log file: $_" }
    }
}

function Stop-AtlasLog {
    [CmdletBinding()]
    param()
    if ($script:AtlasLogContext.FilePath) {
        $footer = @(
            '==========================================',
            "Finished : $((Get-Date).ToString('o'))",
            "Duration : $((Get-Date) - $script:AtlasLogContext.Started)",
            '=========================================='
        ) -join [Environment]::NewLine
        try { $footer | Out-File -FilePath $script:AtlasLogContext.FilePath -Append -Encoding utf8 } catch {}
        $path = $script:AtlasLogContext.FilePath
        $script:AtlasLogContext.FilePath = $null
        $script:AtlasLogContext.Started = $null
        $path
    }
}

function Get-AtlasErrorRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Management.Automation.ErrorRecord]$Record)
    [PSCustomObject]@{
        Message    = $Record.Exception.Message
        Category   = $Record.CategoryInfo.Category
        ScriptName = $Record.InvocationInfo.ScriptName
        Line       = $Record.InvocationInfo.ScriptLineNumber
        Column     = $Record.InvocationInfo.OffsetInLine
        Position   = $Record.InvocationInfo.PositionMessage
    }
}

function Invoke-AtlasSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        [string]$Description = 'operation'
    )
    try {
        Write-AtlasLog "BEGIN: $Description"
        & $ScriptBlock
        Write-AtlasLog "END:   $Description" 'SUCCESS'
    }
    catch {
        $err = Get-AtlasErrorRecord $_
        Write-AtlasLog "FAILED: $Description - $($err.Message) at $($err.ScriptName):$($err.Line)" 'ERROR'
        throw
    }
}

function Invoke-AtlasLoggedCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [switch]$Wait = $true,
        [switch]$NoNewWindow = $true
    )
    $argStr = ($ArgumentList | ForEach-Object { '"' + $_ + '"' }) -join ' '
    Write-AtlasLog "RUN: `"$FilePath`" $argStr" 'DEBUG'
    if ($Wait) {
        $out = & $FilePath @ArgumentList 2>&1
        foreach ($line in $out) { Write-AtlasLog "  | $line" 'DEBUG' }
        if ($LASTEXITCODE -ne 0) {
            throw "Command `"$FilePath`" exited with code $LASTEXITCODE"
        }
        return $out
    }
    else {
        Start-Process -FilePath $FilePath -ArgumentList $ArgumentList
    }
}

# -----------------------------------------------------------------------------
# Safe registry wrappers (no silent key-not-found / permission surprises)
# -----------------------------------------------------------------------------

function Test-AtlasRegistryPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    try {
        $null = Get-Item -LiteralPath $Path -ErrorAction Stop
        $true
    }
    catch { $false }
}

function Get-AtlasRegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )
    if (-not (Test-AtlasRegistryPath -Path $Path)) { return $null }
    $item = Get-ItemProperty -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $item -or -not (Get-Member -InputObject $item -Name $Name -MemberType NoteProperty)) { return $null }
    $item.$Name
}

function Set-AtlasRegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [ValidateSet('REG_SZ','REG_DWORD','REG_QWORD','REG_MULTI_SZ','REG_BINARY','REG_EXPAND_SZ')]
        [string]$Type = 'REG_SZ'
    )
    if (-not (Test-AtlasRegistryPath -Path $Path)) {
        Write-AtlasLog "Creating registry path: $Path" 'DEBUG'
        New-Item -Path $Path -Force | Out-Null
    }
    $typeMap = @{
        'REG_SZ' = [Microsoft.Win32.RegistryValueKind]::String
        'REG_DWORD' = [Microsoft.Win32.RegistryValueKind]::DWord
        'REG_QWORD' = [Microsoft.Win32.RegistryValueKind]::QWord
        'REG_MULTI_SZ' = [Microsoft.Win32.RegistryValueKind]::MultiString
        'REG_BINARY' = [Microsoft.Win32.RegistryValueKind]::Binary
        'REG_EXPAND_SZ' = [Microsoft.Win32.RegistryValueKind]::ExpandString
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $typeMap[$Type] -Force | Out-Null
}

function Remove-AtlasRegistryValueSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )
    if (Test-AtlasRegistryPath -Path $Path) {
        Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction SilentlyContinue
    }
}

# -----------------------------------------------------------------------------
# Integrity / hashing
# -----------------------------------------------------------------------------

function Get-AtlasFileHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('SHA256','SHA384','SHA512','SHA1','MD5')]
        [string]$Algorithm = 'SHA256'
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "File not found: $Path"
    }
    (Get-FileHash -LiteralPath $Path -Algorithm $Algorithm).Hash.ToUpperInvariant()
}

<#
.SYNOPSIS
    Reads a manifest of expected hashes and verifies them against disk.

.PARAMETER ManifestPath
    Path to a file in the format produced by scripts/ci/New-AtlasHashManifest.ps1:
        <SHA256>  <relative path>

.PARAMETER RootPath
    Directory that relative paths are rooted in.
#>
function Compare-AtlasHashTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$RootPath
    )
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Manifest not found: $ManifestPath"
    }
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($raw in Get-Content -LiteralPath $ManifestPath -ErrorAction Stop) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        $parts = $line -split '\s+', 2
        if ($parts.Count -ne 2) { continue }
        $expected = $parts[0].ToUpperInvariant()
        $rel = $parts[1].Trim()
        $abs = Join-Path $RootPath $rel
        $entry = [PSCustomObject]@{
            Path = $rel
            ExpectedHash = $expected
            ActualHash = $null
            Status = 'Missing'
        }
        if (Test-Path -LiteralPath $abs -PathType Leaf) {
            $actual = Get-AtlasFileHash -Path $abs
            $entry.ActualHash = $actual
            $entry.Status = if ($actual -eq $expected) { 'Ok' } else { 'Mismatch' }
        }
        $results.Add($entry)
    }
    $results
}

# -----------------------------------------------------------------------------
# Playbook structural validation helpers (used by CI and health check)
# -----------------------------------------------------------------------------

function Test-AtlasYamlPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    Test-Path -LiteralPath $Path -PathType Leaf
}

function Test-AtlasReferencedFiles {
    <#
    .SYNOPSIS
        Scans a YAML file for references to .cmd/.ps1/.exe/.reg files relative to
        a given exeDir and returns a list of every reference with whether it
        exists. Used by scripts/ci/Validate-AtlasPlaybook.ps1.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$YamlPath,
        [Parameter(Mandatory)][string]$PlaybookRoot
    )
    $content = Get-Content -LiteralPath $YamlPath -Raw -ErrorAction Stop
    $matches = [regex]::Matches($content, "(?m)['`"]\\?([^'"`]*?\.(?:cmd|ps1|exe|reg|cab|psm1|bat|theme))['`"]")
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($m in $matches) {
        $rel = $m.Groups[1].Value -replace '^\\',''
        # Normalise backslashes
        $rel = $rel -replace '/','\'
        $candidates = @()
        if ($rel.StartsWith('.')) {
            $candidates += (Join-Path (Split-Path $YamlPath -Parent) $rel)
            $candidates += (Join-Path (Split-Path $YamlPath -Parent) 'Executables' $rel)
        }
        else {
            $candidates += (Join-Path $PlaybookRoot $rel)
            $candidates += (Join-Path $PlaybookRoot 'Executables' $rel)
        }
        $found = $false
        foreach ($c in ($candidates | Select-Object -Unique)) {
            if (Test-Path -LiteralPath $c -PathType Leaf) { $found = $true; break }
        }
        $results.Add([PSCustomObject]@{
            YamlPath = Split-Path $YamlPath -Leaf
            ReferencedPath = $rel
            ResolvedPath = if ($found) { $c } else { $null }
            Exists = $found
        })
    }
    $results
}

Export-ModuleMember -Function @(
    'Write-AtlasLog','Start-AtlasLog','Stop-AtlasLog','Invoke-AtlasLoggedCommand',
    'Invoke-AtlasSafe','Test-AtlasAdmin','Get-AtlasErrorRecord',
    'Test-AtlasTrustedInstaller','Get-AtlasSystemArchitecture',
    'Get-AtlasRegistryValue','Set-AtlasRegistryValue','Remove-AtlasRegistryValueSafe','Test-AtlasRegistryPath',
    'Get-AtlasWindowsDirectory','Get-AtlasModulesDirectory','Get-AtlasDesktopDirectory','Get-AtlasLogDirectory',
    'Get-AtlasFileHash','Compare-AtlasHashTable',
    'Test-AtlasYamlPath','Test-AtlasReferencedFiles'
)
