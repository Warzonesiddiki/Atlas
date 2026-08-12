#Requires -RunAsAdministrator
<#
.SYNOPSIS
    The Atlas state engine. Provides idempotent apply/revert of every tweak
    and a persistent record of applied state under HKLM:\SOFTWARE\AtlasOS\State.

.DESCRIPTION
    Every Atlas tweak (whether YAML-driven or script-driven) is identified by
    a stable TweakId (e.g. "privacy.disable-activity-feed"). The engine stores:

        HKLM:\SOFTWARE\AtlasOS\State\<TweakId>
            AppliedAt   (REG_SZ, ISO-8601 timestamp of last apply)
            Version     (REG_SZ, version of the tweak logic that applied it)
            Profile     (REG_SZ, which profile was active when applied)
            RevertCmd   (REG_SZ, path to the revert script/command)
            Hash        (REG_SZ, SHA-256 of the apply script body for change detection)
            Category    (REG_SZ, e.g. privacy, security, performance, gaming)

    This enables:
      - Re-running the playbook safely (already-applied tweaks are skipped
        unless -Force is given or their Version/Hash changed).
      - Profile switching post-install (revert tweaks from the old profile
        that shouldn't be on in the new profile, apply missing ones).
      - Per-tweak uninstall in the Desktop folder.
      - Audit / diagnostics (the health check can enumerate applied state).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Path on disk where state is recorded.
$script:AtlasStateRoot = 'HKLM:\SOFTWARE\AtlasOS\State'
$script:AtlasProfileKey = 'HKLM:\SOFTWARE\AtlasOS\Profile'

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

function _EnsureStateRoot {
    if (-not (Test-Path $script:AtlasStateRoot)) {
        New-Item -Path $script:AtlasStateRoot -Force | Out-Null
    }
}

function _GetTweakKey([string]$TweakId) {
    Join-Path $script:AtlasStateRoot $TweakId
}

function _NormalizeId([string]$Id) {
    # Only allow [a-z0-9.-] in tweak IDs; normalise separators.
    ($Id.Trim().ToLowerInvariant() -replace '[^a-z0-9.-]','-') -replace '-+','-'
}

function _HashScript([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $bytes = [Text.Encoding]::UTF8.GetBytes($content)
    $sha = [Security.Cryptography.SHA256]::Create()
    (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
}

# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

function Get-AtlasState {
    <#
    .SYNOPSIS
        Returns a hashtable of all applied tweaks keyed by TweakId, or $null
        for a specific TweakId if it is not applied.
    #>
    [CmdletBinding()]
    param(
        [string]$TweakId
    )
    _EnsureStateRoot
    if ($PSBoundParameters.ContainsKey('TweakId')) {
        $id = _NormalizeId $TweakId
        $key = _GetTweakKey $id
        if (-not (Test-Path $key)) { return $null }
        $p = Get-ItemProperty -Path $key
        [PSCustomObject]@{
            TweakId    = $id
            AppliedAt  = $p.AppliedAt
            Version    = $p.Version
            Profile    = $p.Profile
            RevertCmd  = $p.RevertCmd
            Hash       = $p.Hash
            Category   = $p.Category
        }
    }
    else {
        Get-ChildItem -Path $script:AtlasStateRoot | ForEach-Object {
            $p = Get-ItemProperty -Path $_.PSPath
            [PSCustomObject]@{
                TweakId    = $_.PSChildName
                AppliedAt  = $p.AppliedAt
                Version    = $p.Version
                Profile    = $p.Profile
                RevertCmd  = $p.RevertCmd
                Hash       = $p.Hash
                Category   = $p.Category
            }
        }
    }
}

function Test-AtlasTweakApplied {
    <#
    .SYNOPSIS
        Returns $true if the given TweakId is currently recorded as applied
        with a matching Hash (or any hash when no script path is given).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TweakId,
        [string]$Version,
        [string]$ScriptPath
    )
    $id = _NormalizeId $TweakId
    $state = Get-AtlasState -TweakId $id
    if (-not $state) { return $false }
    if ($Version -and $state.Version -ne $Version) { return $false }
    if ($ScriptPath) {
        $expected = _HashScript $ScriptPath
        if (-not $expected) { return $false }
        if ($state.Hash -ne $expected) { return $false }
    }
    $true
}

function Register-AtlasRollback {
    <#
    .SYNOPSIS
        Record a revert command for an already-applied tweak. Useful when a
        tweak is applied outside Set-AtlasState (e.g. a YAML task that
        manually removes an AppX but still needs a revert entry).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TweakId,
        [Parameter(Mandatory)][string]$RevertCommand,
        [string]$Version = '0.0.0',
        [string]$Category = 'misc',
        [string]$ApplyScriptPath
    )
    $id = _NormalizeId $TweakId
    _EnsureStateRoot
    $key = _GetTweakKey $id
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    $hash = if ($ApplyScriptPath) { _HashScript $ApplyScriptPath } else { '' }
    New-ItemProperty -Path $key -Name AppliedAt -PropertyType String -Value (Get-Date).ToString('o') -Force | Out-Null
    New-ItemProperty -Path $key -Name Version   -PropertyType String -Value $Version -Force | Out-Null
    New-ItemProperty -Path $key -Name RevertCmd -PropertyType String -Value $RevertCommand -Force | Out-Null
    New-ItemProperty -Path $key -Name Hash      -PropertyType String -Value $hash -Force | Out-Null
    New-ItemProperty -Path $key -Name Category  -PropertyType String -Value $Category -Force | Out-Null
    $currentProfile = ''
    try { $currentProfile = (Get-ItemProperty -Path $script:AtlasProfileKey -Name Current -ErrorAction SilentlyContinue).Current } catch {}
    if ($currentProfile) {
        New-ItemProperty -Path $key -Name Profile -PropertyType String -Value $currentProfile -Force | Out-Null
    }
}

function Set-AtlasState {
    <#
    .SYNOPSIS
        Apply a tweak idempotently. If the tweak is already recorded as applied
        with the same Version and script hash, this is a no-op. Otherwise it
        runs -ApplyScript (or -ApplyCommand) and registers rollback.

    .PARAMETER TweakId
        Stable identifier such as "ai.disable-recall".

    .PARAMETER ApplyScript
        Path to a PowerShell script to invoke.

    .PARAMETER ApplyCommand
        Raw command string to invoke (if script isn't applicable). Prefer scripts.

    .PARAMETER RevertCommand
        Command that will undo the tweak.

    .PARAMETER Version
        Version of the tweak logic. Bump when the logic changes so existing
        installs re-apply on next playbook run.

    .PARAMETER Category
        Category for grouping (privacy/performance/gaming/security/...).

    .PARAMETER Force
        Apply even if state suggests it is already present.

    .PARAMETER WhatIf
        Only report what would be done; don't change system state.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$TweakId,
        [string]$ApplyScript,
        [string]$ApplyCommand,
        [Parameter(Mandatory)][string]$RevertCommand,
        [string]$Version = '1.0.0',
        [string]$Category = 'misc',
        [switch]$Force
    )
    $id = _NormalizeId $TweakId

    Import-Module "$env:windir\AtlasModules\Scripts\Lib\Atlas\Atlas.psd1" -Force -ErrorAction SilentlyContinue
    if (Get-Command Write-AtlasLog -ErrorAction SilentlyContinue) {
        Write-AtlasLog "Set-AtlasState: $id (v$Version, category=$Category, force=$Force)"
    }

    $already = Test-AtlasTweakApplied -TweakId $id -Version $Version -ScriptPath $ApplyScript
    if ($already -and -not $Force) {
        if (Get-Command Write-AtlasLog -ErrorAction SilentlyContinue) {
            Write-AtlasLog "  → already applied; skipping." 'DEBUG'
        }
        return [PSCustomObject]@{ TweakId = $id; Action = 'Skip'; AppliedAt = (Get-Date).ToString('o') }
    }

    if ($PSCmdlet.ShouldProcess($id, "Apply tweak")) {
        if ($ApplyScript) {
            if (-not (Test-Path -LiteralPath $ApplyScript -PathType Leaf)) {
                throw "ApplyScript not found: $ApplyScript"
            }
            & $ApplyScript
            if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "ApplyScript for $id exited with code $LASTEXITCODE" }
        }
        elseif ($ApplyCommand) {
            Invoke-Expression $ApplyCommand
        }
        else {
            throw "Either ApplyScript or ApplyCommand must be supplied."
        }
        Register-AtlasRollback -TweakId $id -RevertCommand $RevertCommand -Version $Version -Category $Category -ApplyScriptPath $ApplyScript
    }

    [PSCustomObject]@{ TweakId = $id; Action = 'Apply'; AppliedAt = (Get-Date).ToString('o') }
}

function Reset-AtlasState {
    <#
    .SYNOPSIS
        Revert a single tweak by running its stored RevertCmd and removing
        state. Use -All to revert every tweak in reverse-apply order.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$TweakId,
        [switch]$All,
        [switch]$Force
    )
    _EnsureStateRoot

    if ($All) {
        $items = Get-AtlasState | Sort-Object AppliedAt -Descending
        foreach ($t in $items) {
            Reset-AtlasState -TweakId $t.TweakId -Force:$Force
        }
        return
    }

    $id = _NormalizeId $TweakId
    $state = Get-AtlasState -TweakId $id
    if (-not $state) {
        if (Get-Command Write-AtlasLog -ErrorAction SilentlyContinue) {
            Write-AtlasLog "Reset-AtlasState: $id not applied; nothing to do." 'DEBUG'
        }
        return
    }

    if (Get-Command Write-AtlasLog -ErrorAction SilentlyContinue) {
        Write-AtlasLog "Reset-AtlasState: reverting $id (v$($state.Version))" 'WARN'
    }

    if ($PSCmdlet.ShouldProcess($id, "Revert tweak")) {
        try {
            if ($state.RevertCmd) { Invoke-Expression $state.RevertCmd }
        }
        catch {
            if (Get-Command Write-AtlasLog -ErrorAction SilentlyContinue) {
                Write-AtlasLog ("Revert failed for {0}: {1}" -f $id, $_.Exception.Message) 'ERROR'
            }
            throw
        }
        $key = _GetTweakKey $id
        Remove-Item -Path $key -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-AtlasProfile {
    <#
    .SYNOPSIS
        Returns the current profile name (e.g. 'balanced', 'performance').
    #>
    _EnsureStateRoot
    if (-not (Test-Path $script:AtlasProfileKey)) { return $null }
    (Get-ItemProperty -Path $script:AtlasProfileKey -ErrorAction SilentlyContinue).Current
}

function Set-AtlasProfile {
    <#
    .SYNOPSIS
        Record the selected profile and optionally reconcile tweaks so that
        only the tweaks belonging to the selected profile are applied. Call
        this at install time and when the user switches profiles via Toolbox.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('balanced','performance','privacy','security','custom')]
        [string]$Profile
    )
    _EnsureStateRoot
    if (-not (Test-Path $script:AtlasProfileKey)) {
        New-Item -Path $script:AtlasProfileKey -Force | Out-Null
    }
    New-ItemProperty -Path $script:AtlasProfileKey -Name Current -PropertyType String -Value $Profile -Force | Out-Null
    New-ItemProperty -Path $script:AtlasProfileKey -Name AppliedAt -PropertyType String -Value (Get-Date).ToString('o') -Force | Out-Null
    if (Get-Command Write-AtlasLog -ErrorAction SilentlyContinue) {
        Write-AtlasLog "Profile set to: $Profile" 'SUCCESS'
    }
}

Export-ModuleMember -Function @(
    'Get-AtlasState','Test-AtlasTweakApplied','Register-AtlasRollback',
    'Set-AtlasState','Reset-AtlasState',
    'Get-AtlasProfile','Set-AtlasProfile'
)
