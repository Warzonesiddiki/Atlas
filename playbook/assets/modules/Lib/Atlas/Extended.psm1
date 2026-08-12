# Atlas PowerShell Module - services, AppX, policy, firewall, UI helpers
# Extends the core module defined in Atlas.psm1. Dot-sourced from there.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# Services
# -----------------------------------------------------------------------------

function Test-AtlasServiceExists {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    [bool](Get-Service -Name $Name -ErrorAction SilentlyContinue)
}

<#
.SYNOPSIS
    Sets a Windows service start type and backs up the prior state under
    HKLM:\SOFTWARE\AtlasOS\ServiceBackup so Reset-AtlasServices can restore it.
#>
function Set-AtlasServiceStart {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('Boot','System','Automatic','Manual','Disabled','DelayedAutoStart')]
        [string]$Startup
    )
    if (-not (Test-AtlasServiceExists -Name $Name)) {
        Write-AtlasLog "Service $Name does not exist; skipping." 'DEBUG'
        return
    }
    $svc = Get-Service -Name $Name
    $wmi = Get-CimInstance Win32_Service -Filter "Name='$Name'"
    $currentStart = $wmi.StartMode
    # Record backup if not already recorded
    $backupKey = "HKLM:\SOFTWARE\AtlasOS\ServiceBackup\$Name"
    if (-not (Test-Path $backupKey)) {
        if (-not (Test-Path 'HKLM:\SOFTWARE\AtlasOS\ServiceBackup')) {
            New-Item 'HKLM:\SOFTWARE\AtlasOS\ServiceBackup' -Force | Out-Null
        }
        New-Item -Path $backupKey -Force | Out-Null
        New-ItemProperty -Path $backupKey -Name OriginalStart -PropertyType String -Value $currentStart -Force | Out-Null
    }
    # Map friendly names to sc config numeric start types
    $startMap = @{
        'Boot'           = 0
        'System'         = 1
        'Automatic'      = 2
        'Manual'         = 3
        'Disabled'       = 4
        'DelayedAutoStart'= 2
    }
    $code = $startMap[$Startup]
    if ($PSCmdlet.ShouldProcess($Name, "Set start type to $Startup")) {
        if ($Startup -eq 'DelayedAutoStart') {
            & sc.exe config $Name start= auto *> $null
            & sc.exe config $Name depend= / + DelayedAutoStart 2>$null
            Set-ItemProperty -Path ("HKLM:\SYSTEM\CurrentControlSet\Services\$Name") -Name DelayedAutoStart -Value 1 -Type DWord -Force
        }
        else {
            & sc.exe config $Name start= $("boot","system","auto","demand","disabled")[$code] *> $null
        }
        if ($LASTEXITCODE -ne 0) { Write-AtlasLog "sc config for $Name returned $LASTEXITCODE" 'WARN' }
        Write-AtlasLog "Service ${Name}: start -> ${Startup}"
    }
}

function Restore-AtlasServices {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $key = 'HKLM:\SOFTWARE\AtlasOS\ServiceBackup'
    if (-not (Test-Path $key)) { Write-AtlasLog 'No service backup to restore.'; return }
    foreach ($svcKey in (Get-ChildItem $key)) {
        $name = $svcKey.PSChildName
        $orig = (Get-ItemProperty -Path $svcKey.PSPath).OriginalStart
        if ($orig -and (Test-AtlasServiceExists $name)) {
            Write-AtlasLog "Restoring service ${name} -> ${orig}"
            if ($PSCmdlet.ShouldProcess($name, "Restore start $orig")) {
                $scStart = switch ($orig) {
                    'Auto'  { 'auto' }
                    'Manual'{ 'demand' }
                    'Disabled' { 'disabled' }
                    'Boot'  { 'boot' }
                    'System'{ 'system' }
                    default { 'demand' }
                }
                & sc.exe config $name start= $scStart *> $null
            }
        }
        Remove-Item $svcKey.PSPath -Recurse -Force
    }
}

function Backup-AtlasServices {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ExportPath
    )
    # Export all services configuration to a .reg file for out-of-band restore
    & reg.exe export 'HKLM\SYSTEM\CurrentControlSet\Services' $ExportPath /y *> $null
}

# -----------------------------------------------------------------------------
# AppX
# -----------------------------------------------------------------------------

function Remove-AtlasAppx {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$Deprovision
    )
    foreach ($pkg in (Get-AppxPackage -AllUsers -Name $Name -ErrorAction SilentlyContinue)) {
        if ($PSCmdlet.ShouldProcess($pkg.PackageFullName, 'Remove AppX')) {
            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue
        }
    }
    if ($Deprovision) {
        foreach ($prov in (Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $Name })) {
            if ($PSCmdlet.ShouldProcess($prov.DisplayName, 'Deprovision')) {
                Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction SilentlyContinue | Out-Null
            }
        }
    }
}

function Repair-AtlasAppx {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    Get-AppxPackage -AllUsers -Name $Name -ErrorAction SilentlyContinue | ForEach-Object {
        Write-AtlasLog "Re-registering $($_.Name)"
        Add-AppxPackage -Register -DisableDevelopmentMode "$($_.InstallLocation)\AppxManifest.xml" -ErrorAction SilentlyContinue
    }
}

function Get-AtlasAppxProvisioned {
    [CmdletBinding()]
    param()
    Get-AppxProvisionedPackage -Online | Select-Object DisplayName, PackageName
}

# -----------------------------------------------------------------------------
# Policy (registry under Policies\...) + tracking
# -----------------------------------------------------------------------------

function Set-AtlasPolicyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SubKey,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [ValidateSet('REG_SZ','REG_DWORD','REG_QWORD','REG_MULTI_SZ','REG_BINARY','REG_EXPAND_SZ')]
        [string]$Type = 'REG_DWORD'
    )
    # Write to HKLM\SOFTWARE\Policies\... (or HKCU if the path starts with HKCU)
    $path = if ($SubKey -match '^HK(CU|LM|CR|U|CC)\\') { $SubKey } else { Join-Path 'HKLM:\SOFTWARE\Policies' $SubKey }
    # Record to PolicyBackup for revert
    $relKey = $path -replace '^HKLM:\\SOFTWARE\\Policies\\',''
    $backupKey = "HKLM:\SOFTWARE\AtlasOS\PolicyBackup\$relKey"
    if (-not (Test-Path $backupKey)) {
        if (-not (Test-Path (Split-Path $backupKey -Parent))) {
            New-Item -Path (Split-Path $backupKey -Parent) -Force -ErrorAction SilentlyContinue | Out-Null
        }
        New-Item -Path $backupKey -Force -ErrorAction SilentlyContinue | Out-Null
        $existing = Get-AtlasRegistryValue -Path $path -Name $Name
        New-ItemProperty -Path $backupKey -Name $Name -Value ($existing -join '|') -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Set-AtlasRegistryValue -Path $path -Name $Name -Value $Value -Type $Type
}

# -----------------------------------------------------------------------------
# Firewall
# -----------------------------------------------------------------------------

function Add-AtlasFirewallRule {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [ValidateSet('Block','Allow')][string]$Action='Block',
        [ValidateSet('Inbound','Outbound','Any')][string]$Direction='Outbound',
        [string[]]$RemoteAddresses,
        [string]$Protocol='Any',
        [string]$Profile='Any'
    )
    if (Get-NetFirewallRule -Name $Name -ErrorAction SilentlyContinue) {
        Write-AtlasLog "Firewall rule $Name already exists; skipping." 'DEBUG'
        return
    }
    if ($PSCmdlet.ShouldProcess($Name, "Add firewall rule ($Direction $Action)")) {
        $params = @{ Name=$Name; DisplayName=$Name; Direction=$Direction; Action=$Action; Profile=$Profile; Enabled='True'; ErrorAction='Stop' }
        if ($RemoteAddresses) { $params['RemoteAddress'] = $RemoteAddresses }
        New-NetFirewallRule @params | Out-Null
        Write-AtlasLog "Added firewall rule $Name ($Direction $Action)"
    }
}

# -----------------------------------------------------------------------------
# Authenticode / signature verification
# -----------------------------------------------------------------------------

function Test-AtlasSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$ExpectedThumbprint
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "File not found: $Path" }
    $sig = Get-AuthenticodeSignature -FilePath $Path
    if ($sig.Status -ne 'Valid') {
        throw "Authenticode signature invalid for $Path ($($sig.StatusMessage))"
    }
    if ($ExpectedThumbprint -and $sig.SignerCertificate.Thumbprint -ne $ExpectedThumbprint) {
        throw "Signer thumbprint mismatch. Expected $ExpectedThumbprint, got $($sig.SignerCertificate.Thumbprint)"
    }
    $true
}

# -----------------------------------------------------------------------------
# Build / platform detection
# -----------------------------------------------------------------------------

function Test-AtlasIsLaptop {
    [CmdletBinding()]
    param()
    $cs = Get-CimInstance Win32_ComputerSystem
    $cs.PCSystemType -eq 2 -or [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
}

function Test-AtlasIsVM {
    [CmdletBinding()]
    param()
    $cs = Get-CimInstance Win32_ComputerSystem
    $model = ($cs.Model + ' ' + $cs.Manufacturer).ToLowerInvariant()
    if ($model -match 'virtual|vmware|qemu|kvm|virtualbox|hyper-v|innotek') { return $true }
    $false
}

function Get-AtlasWindowsBuild {
    [CmdletBinding()]
    param()
    [int]((Get-CimInstance Win32_OperatingSystem).BuildNumber)
}

function Test-AtlasBuildRangeSatisfied {
    [CmdletBinding()]
    param([int]$MinBuild=0, [int]$MaxBuild=99999)
    $b = Get-AtlasWindowsBuild
    ($b -ge $MinBuild -and $b -le $MaxBuild)
}

# -----------------------------------------------------------------------------
# Minimal UI helpers (only used by post-install scripts; not from playbook core)
# -----------------------------------------------------------------------------

function Write-AtlasHeader {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Title)
    $line = '=' * [Math]::Min($Host.UI.RawUI.WindowSize.Width -as [int], 78)
    Write-Host $line -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor White
    Write-Host $line -ForegroundColor Cyan
}

function Show-AtlasChoiceMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string[]]$Options,
        [int]$DefaultIndex = 0
    )
    Write-AtlasHeader $Title
    for ($i=0; $i -lt $Options.Count; $i++) {
        $prefix = if ($i -eq $DefaultIndex) { "[{0}] (default)" -f ($i+1) } else { "[{0}]" -f ($i+1) }
        Write-Host ("  {0} {1}" -f $prefix, $Options[$i])
    }
    do {
        $sel = Read-Host "Enter selection"
        if ([string]::IsNullOrWhiteSpace($sel)) { return $DefaultIndex }
        $n = 0
        if ([int]::TryParse($sel, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) { return $n-1 }
        Write-Host "Invalid selection." -ForegroundColor Yellow
    } while ($true)
}

function Show-AtlasMessageBox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Caption = 'Atlas',
        [ValidateSet('Info','Warning','Error','Question')][string]$Icon = 'Info'
    )
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        $image = switch ($Icon) {
            'Info' {'Information'} 'Warning' {'Warning'} 'Error' {'Error'} 'Question' {'Question'}
        }
        [System.Windows.MessageBox]::Show($Message, $Caption, 'OK', $image) | Out-Null
    }
    catch {
        Write-Host $Message -ForegroundColor Yellow
    }
}

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------
Export-ModuleMember -Function @(
    'Test-AtlasServiceExists','Set-AtlasServiceStart','Backup-AtlasServices','Restore-AtlasServices',
    'Remove-AtlasAppx','Repair-AtlasAppx','Get-AtlasAppxProvisioned',
    'Set-AtlasPolicyValue',
    'Add-AtlasFirewallRule',
    'Test-AtlasSignature',
    'Test-AtlasIsLaptop','Test-AtlasIsVM','Get-AtlasWindowsBuild','Test-AtlasBuildRangeSatisfied',
    'Write-AtlasHeader','Show-AtlasChoiceMenu','Show-AtlasMessageBox'
)
