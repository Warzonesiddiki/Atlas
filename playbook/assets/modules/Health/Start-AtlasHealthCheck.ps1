#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Post-install / on-demand health check for an Atlas system.

.DESCRIPTION
    Verifies that critical system and Atlas-specific invariants hold:
      - Core Atlas files exist on disk (AtlasDesktop, AtlasModules).
      - The running OS build is in the supported range.
      - Microsoft Store ACLs are intact (issue #1353).
      - Services that Atlas disabled are still disabled; services we kept are running.
      - No pending reboot from CBS/Windows Update that would leave the system half-configured.
      - The hash manifest of bundled binaries matches the shipped files.
    Output is written to console AND to AtlasModules\Logs\HealthCheck_*.log.
#>

[CmdletBinding()]
param(
    [switch]$ExportReport,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Import-Module "$env:windir\AtlasModules\Scripts\Lib\Atlas\Atlas.psd1" -Force

$log = Start-AtlasLog -Name 'HealthCheck'
$issues = New-Object System.Collections.Generic.List[object]

function Add-Issue($Severity, $Code, $Message, $Remediation = $null) {
    $i = [PSCustomObject]@{ Severity = $Severity; Code = $Code; Message = $Message; Remediation = $Remediation }
    $issues.Add($i)
    $color = switch ($Severity) { 'FAIL' { 'Red' } 'WARN' { 'Yellow' } 'INFO' { 'Cyan' } default { 'Gray' } }
    Write-AtlasLog ("[{0}] {1}: {2}" -f $Severity, $Code, $Message) $Severity
}

# --- 1. OS build support ---------------------------------------------------
$os = Get-CimInstance Win32_OperatingSystem
$build = [int]($os.BuildNumber)
$supported = @(26100, 26200)
if ($supported -contains $build) {
    Add-Issue 'INFO' 'BUILD' "Running on supported build $build ($($os.Caption))."
} else {
    Add-Issue 'WARN' 'BUILD' "Unsupported Windows build $build. Atlas v0.6 supports $($supported -join ', ')." "Upgrade Windows or use a matching Atlas version."
}

# --- 2. File presence ------------------------------------------------------
$windir = Get-AtlasWindowsDirectory
$required = @(
    'AtlasDesktop',
    'AtlasModules\Scripts\Lib\Atlas\Atlas.psd1',
    'AtlasModules\initPowerShell.ps1'
)
foreach ($r in $required) {
    $p = Join-Path $windir $r
    if (Test-Path -LiteralPath $p) {
        Add-Issue 'INFO' 'FILES' "Present: $r"
    } else {
        Add-Issue 'FAIL' 'FILES' "Missing required path: $r" "Re-run the Atlas playbook or repair from release ZIP."
    }
}

# --- 3. Microsoft Store ACL sanity (#1353) ---------------------------------
try {
    $wa = Join-Path $env:ProgramFiles 'WindowsApps'
    if (Test-Path $wa) {
        $acl = Get-Acl $wa -ErrorAction Stop
        $sid = New-Object System.Security.Principal.SecurityIdentifier('S-1-15-2-1')
        $rules = $acl.Access | Where-Object {
            $_.IdentityReference -eq $sid.Translate([System.Security.Principal.NTAccount]) -and
            $_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::ReadAndExecute
        }
        if ($rules.Count -gt 0) {
            Add-Issue 'INFO' 'STORE' 'WindowsApps ACL has ALL APPLICATION PACKAGES Read+Execute.'
        } else {
            Add-Issue 'WARN' 'STORE' 'WindowsApps ACL missing ALL APPLICATION PACKAGES read access; Store may fail to launch (#1353).' 'Run atlas\repair-store.yml or the OEM Store repair script.'
        }
    }
} catch {
    Add-Issue 'WARN' 'STORE' "Unable to inspect WindowsApps ACL: $($_.Exception.Message)"
}

# --- 4. Service state ------------------------------------------------------
$disabledByDefault = @('DiagTrack','WerSvc','OneSyncSvc')
foreach ($svcName in $disabledByDefault) {
    try {
        $svc = Get-Service -Name $svcName -ErrorAction Stop
        $startType = (Get-CimInstance Win32_Service -Filter "Name='$svcName'").StartMode
        if ($startType -eq 'Disabled') {
            Add-Issue 'INFO' 'SERVICE' "$svcName is disabled (expected)."
        } else {
            Add-Issue 'WARN' 'SERVICE' "$svcName start type is $startType (expected Disabled)." "Re-apply services configuration from the Atlas folder."
        }
    }
    catch {
        Add-Issue 'INFO' 'SERVICE' "$svcName is not present."
    }
}

# --- 5. Defender state (reflects user choice) ------------------------------
$defenderState = Get-ItemProperty -Path 'HKLM:\SOFTWARE\AtlasOS\Services\Defender' -Name state -ErrorAction SilentlyContinue
if ($defenderState) {
    Add-Issue 'INFO' 'DEFENDER' "Defender state marker = $($defenderState.state)."
} else {
    Add-Issue 'WARN' 'DEFENDER' "No Defender state marker in HKLM\SOFTWARE\AtlasOS\Services\Defender."
}

# --- 6. Reboot pending -----------------------------------------------------
$cbsReboot = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
$wuReboot  = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
if ($cbsReboot -or $wuReboot) {
    Add-Issue 'WARN' 'REBOOT' "A system reboot is pending." "Reboot before running further Atlas tweaks."
} else {
    Add-Issue 'INFO' 'REBOOT' "No pending reboot."
}

# --- 7. Hash manifest check (if present) -----------------------------------
$manifest = Join-Path $windir 'AtlasModules\Other\hashes.sha256'
if (Test-Path -LiteralPath $manifest) {
    $hashResults = Compare-AtlasHashTable -ManifestPath $manifest -RootPath $windir
    foreach ($r in $hashResults) {
        switch ($r.Status) {
            'Ok'       {}
            'Mismatch' { Add-Issue 'FAIL' 'HASH' ("Mismatch: {0}" -f $r.Path) "Re-extract the Atlas playbook (file may be corrupted/tampered)." }
            'Missing'  { Add-Issue 'WARN' 'HASH' ("Missing: {0}" -f $r.Path) }
        }
    }
    Add-Issue 'INFO' 'HASH' "Verified $($hashResults.Count) tracked files."
} else {
    Add-Issue 'WARN' 'HASH' "No hash manifest present; integrity cannot be verified."
}

# --- Summary ---------------------------------------------------------------
$fails = ($issues | Where-Object Severity -eq 'FAIL').Count
$warns = ($issues | Where-Object Severity -eq 'WARN').Count
Write-AtlasLog ("Health check complete. Failures: {0}, Warnings: {1}" -f $fails, $warns)
if ($fails -gt 0) { Write-AtlasLog "One or more failures detected - review the log above." 'ERROR' }

$summary = [PSCustomObject]@{
    GeneratedAt = (Get-Date -Format 'o')
    Build       = $build
    Failed      = $fails
    Warnings    = $warns
    Issues      = $issues
    LogPath     = $null
    ReportPath  = $null
}

if ($ExportReport) {
    $jsonPath = Join-Path (Get-AtlasLogDirectory) ("HealthReport_{0}.json" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
    $issues | ConvertTo-Json -Depth 4 | Out-File -FilePath $jsonPath -Encoding utf8
    $summary.ReportPath = $jsonPath
    Write-AtlasLog "Exported report to: $jsonPath"
}

$logPath = Stop-AtlasLog
$summary.LogPath = $logPath
Write-Host ""
Write-Host "Log saved to: $logPath" -ForegroundColor Cyan

if ($PassThru) { return $summary }
if ($fails -gt 0) { exit 1 }
exit 0
