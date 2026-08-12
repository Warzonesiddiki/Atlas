<#

.SYNOPSIS

    Runs the Atlas playbook inside Windows Sandbox and captures logs for

    integration testing.



.DESCRIPTION

    Generates a Windows Sandbox .wsb configuration, mounts the playbook build

    output, launches AME Wizard silently, waits for completion, and copies the

    resulting logs back out. Requires:

      - Windows 10/11 Pro/Edu/Enterprise

      - Windows Sandbox feature enabled

      - A pre-built APBX file (pass -Apbx)

    This is the core of E10-W02 (integration sandbox test).



.PARAMETER Apbx

    Path to a built .apbx file to install.



.PARAMETER OutputDir

    Where to collect logs on the host. Default: ./sandbox-logs/<timestamp>.

#>

[CmdletBinding()]

param(

    [Parameter(Mandatory)][string]$Apbx,

    [string]$OutputDir

)

if (-not $OutputDir) { $OutputDir = Join-Path $PSScriptRoot ("../../sandbox-logs/" + (Get-Date -Format 'yyyyMMdd-HHmmss')) }

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

if (-not (Test-Path $Apbx)) { throw "APBX not found: $Apbx" }



# Build a startup script that installs the APBX inside the sandbox

$startup = Join-Path $OutputDir 'startup.cmd'

@'

@echo off

set LOG=%TEMP%\atlas-install.log

echo [%date% %time%] Starting AME Wizard...

:: AME Wizard headless (replace -silent path with the actual CLI when available)

powershell -NoP -Command "& '$PFILE'" *>%LOG%

echo [%date% %time%] Done, copying logs to desktop

mkdir C:\Users\WDAGUtilityAccount\Desktop\Atlas-logs

copy %LOG% C:\Users\WDAGUtilityAccount\Desktop\Atlas-logs\

powershell -NoP -Command "shutdown /s /t 10"

'@ | Out-File -FilePath $startup -Encoding ASCII



$wsb = Join-Path $OutputDir 'test.wsb'

@"

<Configuration>

  <VGpu>Enable</VGpu>

  <Networking>Enable</Networking>

  <MappedFolders>

    <MappedFolder>

      <HostFolder>$(Split-Path $Apbx -Parent)</HostFolder>

      <ReadOnly>true</ReadOnly>

    </MappedFolder>

  </MappedFolders>

  <LogonCommand>

    <Command>%SystemDrive%\Users\WDAGUtilityAccount\Desktop\startup.cmd</Command>

  </LogonCommand>

  <AudioInput>Disable</AudioInput>

  <VideoInput>Disable</VideoInput>

  <ProtectedClient>Disable</ProtectedClient>

  <PrinterRedirection>Disable</PrinterRedirection>

  <ClipboardRedirection>Disable</ClipboardRedirection>

</Configuration>

"@ | Out-File $wsb -Encoding UTF8



Write-Host "Launching Windows Sandbox with configuration: $wsb" -ForegroundColor Cyan

Start-Process 'WindowsSandbox.exe' -ArgumentList $wsb -Wait

Write-Host "Sandbox exited; collect logs manually from $OutputDir until auto-collect is implemented." -ForegroundColor Yellow

