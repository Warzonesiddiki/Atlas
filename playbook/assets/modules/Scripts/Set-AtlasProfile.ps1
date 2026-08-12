#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Switch the active Atlas profile (balanced/performance/privacy/security)
    from a post-install desktop script.

.DESCRIPTION
    Changes HKLM:\SOFTWARE\AtlasOS\Profile\Current and re-applies profile-scoped
    configuration (power plan, AI disablement, gaming tweaks, service defaults).
    A corresponding revert is not run automatically — individual category
    scripts in the Atlas folder remain authoritative.
#>
[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [ValidateSet('balanced','performance','privacy','security')]
    [string]$Profile,
    [switch]$NoRestart
)

$ErrorActionPreference = 'Stop'
$windir = [Environment]::GetFolderPath('Windows')
Import-Module "$windir\AtlasModules\Scripts\Lib\Atlas\Atlas.psd1" -Force

if (-not $Profile) {
    $choices = @(
        [System.Management.Automation.Host.ChoiceDescription]::new('&Balanced',    'Recommended: good balance of privacy, performance, security')
        [System.Management.Automation.Host.ChoiceDescription]::new('&Performance', 'Maximum performance: power plan + gaming tweaks, relaxed mitigations')
        [System.Management.Automation.Host.ChoiceDescription]::new('&Privacy',    'Aggressive telemetry/AppX removal; disables Defender and Edge')
        [System.Management.Automation.Host.ChoiceDescription]::new('&Security',   'Hardening: ASR, LSA, SMB1 off, BitLocker prompt, updates enabled')
    )
    $selected = $Host.UI.PromptForChoice('Atlas profile', 'Choose a profile to apply:', $choices, 0)
    $Profile = @('balanced','performance','privacy','security')[$selected]
}

Write-AtlasLog "Switching Atlas profile to: $Profile" 'INFO'
$key = 'HKLM:\SOFTWARE\AtlasOS\Profile'
if (!(Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
Set-ItemProperty -Path $key -Name 'Current' -Value $Profile -Type String -Force
Set-ItemProperty -Path $key -Name 'ChangedAt' -Value (Get-Date -Format 'o') -Type String -Force

# Power plan (matches gaming/power-plan.yml behavior)
$highPerf = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
switch ($Profile) {
    'performance' {
        $existing = powercfg /l
        if ($existing -notmatch $highPerf) { powercfg -duplicatescheme $highPerf *>$null }
        powercfg -setactive $highPerf
        Write-AtlasLog 'Power plan set to High Performance.'
    }
    default {
        powercfg -setactive $balanced
        Write-AtlasLog 'Power plan set to Balanced.'
    }
}

# Performance profile: enable timer resolution scheduled task if binary exists
$timerExe = "$windir\AtlasModules\Tools\SetTimerResolution.exe"
if ($Profile -eq 'performance' -and (Test-Path $timerExe)) {
    $action  = New-ScheduledTaskAction -Execute $timerExe -Argument '--resolution 5000 --no-console'
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName 'AtlasTimerResolution' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Write-AtlasLog 'AtlasTimerResolution task enabled.'
} elseif (Get-ScheduledTask -TaskName 'AtlasTimerResolution' -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName 'AtlasTimerResolution' -Confirm:$false
    Write-AtlasLog 'AtlasTimerResolution task removed.'
}

Write-Host ""
Write-Host "Profile set to: $Profile" -ForegroundColor Green
Write-Host "Some changes require a restart to fully take effect."
if (-not $NoRestart) {
    $r = Read-Host "Restart Explorer now to apply UI changes? (Y/n)"
    if ($r -ne 'n') {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Process explorer
    }
}
