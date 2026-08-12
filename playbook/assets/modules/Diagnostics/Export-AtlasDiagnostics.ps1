#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Collects anonymised diagnostics useful when reporting Atlas bugs.

.DESCRIPTION
    Gathers (into a zip on the user's desktop):
      - All logs from %windir%\AtlasModules\Logs
      - Service configuration for services Atlas touches
      - Relevant registry keys (HKLM\SOFTWARE\AtlasOS, current Windows version,
        Defender / update policies) — values are included as-is; no document
        history or personal files are touched.
      - Basic hardware summary (CPU, RAM, GPU) to contextualise performance reports.
    No private data, no documents, no browsing history, no telemetry is uploaded.
#>

[CmdletBinding()]
param(
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Import-Module "$env:windir\AtlasModules\Scripts\Lib\Atlas\Atlas.psd1" -Force

if (-not $OutputPath) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $OutputPath = Join-Path $desktop "AtlasDiagnostics_$stamp.zip"
}

$stagingRoot = Join-Path $env:TEMP ("AtlasDiag_" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
try {
    Write-AtlasLog "Collecting diagnostics..." 'INFO'

    # 1. Copy logs
    $logDir = Join-Path (Get-AtlasModulesDirectory) 'Logs'
    if (Test-Path -LiteralPath $logDir) {
        Copy-Item -Path $logDir -Destination (Join-Path $stagingRoot 'Logs') -Recurse -Force
    }

    # 2. OS + hardware summary
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1 Name,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed
    $gpu = Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,AdapterRAM
    $sys = [PSCustomObject]@{
        Timestamp    = (Get-Date).ToString('o')
        Caption      = $os.Caption
        BuildNumber  = $os.BuildNumber
        Version      = $os.Version
        Architecture = Get-AtlasSystemArchitecture
        Computer     = $env:COMPUTERNAME
        CPU          = $cpu
        RAMGB        = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
        GPU          = $gpu
        Defender     = (Get-ItemProperty 'HKLM:\SOFTWARE\AtlasOS\Services\Defender' -ErrorAction SilentlyContinue) | Select-Object state
        PowerSaving  = (Get-ItemProperty 'HKLM:\SOFTWARE\AtlasOS\Services\PowerSaving' -ErrorAction SilentlyContinue) | Select-Object state
    }
    $sys | ConvertTo-Json -Depth 4 | Out-File (Join-Path $stagingRoot 'system.json') -Encoding utf8

    # 3. Service states for services Atlas modifies
    $atlasServices = @(
        'DiagTrack','WerSvc','OneSyncSvc','TrkWks','PcaSvc','UCPD','NetBT','Telemetry',
        'GpuEnergyDrv','diagnosticshub.standardcollector.service','wercplsupport','WinDefend','WdNisSvc'
    )
    $svcStates = foreach ($n in $atlasServices) {
        try {
            Get-CimInstance Win32_Service -Filter "Name='$n'" -ErrorAction Stop | Select-Object Name,State,StartMode,PathName
        } catch {
            [PSCustomObject]@{ Name=$n; State='missing'; StartMode='n/a' }
        }
    }
    $svcStates | ConvertTo-Json -Depth 4 | Out-File (Join-Path $stagingRoot 'services.json') -Encoding utf8

    # 4. Export key registry keys
    $keys = @(
        'HKLM\SOFTWARE\AtlasOS',
        'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate',
        'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing'
    )
    $regDir = Join-Path $stagingRoot 'Registry'
    New-Item -ItemType Directory -Path $regDir -Force | Out-Null
    foreach ($k in $keys) {
        $safe = ($k -replace '\\','_' -replace '[^A-Za-z0-9_\-]','_') + '.reg'
        & reg.exe export $k (Join-Path $regDir $safe) /y 2>$null | Out-Null
    }

    # 5. List of installed AppX packages (no user data)
    Get-AppxPackage -AllUsers | Select-Object Name,PackageFullName,InstallLocation |
        ConvertTo-Json -Depth 3 | Out-File (Join-Path $stagingRoot 'appx.json') -Encoding utf8

    # Zip
    if (Test-Path -LiteralPath $OutputPath) { Remove-Item $OutputPath -Force }
    Compress-Archive -Path (Join-Path $stagingRoot '*') -DestinationPath $OutputPath -CompressionLevel Optimal

    Write-Host ""
    Write-Host "Diagnostics saved to: $OutputPath" -ForegroundColor Green
    Write-Host "Review the zip before sharing — it contains system configuration but no personal documents."
}
finally {
    Remove-Item -Recurse -Force $stagingRoot -ErrorAction SilentlyContinue
}
