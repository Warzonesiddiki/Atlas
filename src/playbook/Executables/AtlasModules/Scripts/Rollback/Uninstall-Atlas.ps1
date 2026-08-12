#Requires -RunAsAdministrator

<#

.SYNOPSIS

    Master uninstall script for Atlas.

    1. Runs all available category revert scripts.

    2. Restores services from winServices.reg.

    3. Removes scheduled tasks added by Atlas.

    4. Removes %windir%\AtlasDesktop and %windir%\AtlasModules (with prompt).

    5. Removes HKLM\SOFTWARE\AtlasOS.

    6. Warns that CAB-removed components cannot be restored without repair install.



.NOTES

    Requires admin. This is destructive; a log is written to

    $env:TEMP\AtlasUninstall.log.

#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]

param([switch]$Force)



Set-StrictMode -Version Latest

$ErrorActionPreference = 'Continue'



$windir = [Environment]::GetFolderPath('Windows')

$log = Join-Path $env:TEMP 'AtlasUninstall.log'

Start-Transcript -Path $log -Force | Out-Null



try {

    Write-Host "Atlas Uninstall" -ForegroundColor Red

    Write-Host "===============" -ForegroundColor Red

    Write-Host "This will remove Atlas configuration files and revert services and policies." -ForegroundColor Yellow

    Write-Host "Components removed via CAB packages cannot be restored by this script; use" -ForegroundColor Yellow

    Write-Host "Windows in-place upgrade if you need them back." -ForegroundColor Yellow

    if (-not $Force) {

        $r = Read-Host "Type UNINSTALL to proceed"

        if ($r -ne 'UNINSTALL') { Write-Host "Aborted." ; exit 2 }

    }



    # 1. Run category revert scripts

    $revertRoot = Join-Path $windir 'AtlasModules\Scripts\Rollback'

    if (Test-Path $revertRoot) {

        foreach ($revert in (Get-ChildItem -Path $revertRoot -Filter *.cmd -Recurse)) {

            Write-Host "[+] Running $($revert.Name)..." -ForegroundColor Cyan

            & $revert.FullName /silent

        }

    }



    # 2. Restore services from backup .reg

    $svcReg = Join-Path $windir 'AtlasModules\Other\winServices.reg'

    if (Test-Path $svcReg) {

        Write-Host "[+] Restoring services from $svcReg..." -ForegroundColor Cyan

        & reg.exe import $svcReg 2>$null | Out-Null

    }

    else {

        Write-Warning "Service backup not found; skipping."

    }



    # 3. Restore policy values

    Write-Host "[+] Removing Atlas-set policies..." -ForegroundColor Cyan

    Get-ChildItem 'HKLM:\SOFTWARE\Policies' -Recurse -ErrorAction SilentlyContinue |

        Where-Object { $_.Name -match 'Atlas' -or (Get-ItemProperty -Path $_.PSPath -Name 'Atlasset*' -ErrorAction SilentlyContinue) } |

        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue



    # 4. Remove Atlas scheduled tasks (timer resolution at least)

    Get-ScheduledTask -TaskName 'Atlas*' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue



    # 5. Remove files

    Write-Host "[+] Removing Atlas folders..." -ForegroundColor Cyan

    foreach ($p in @(

        (Join-Path $windir 'AtlasDesktop'),

        (Join-Path $windir 'AtlasModules')

    )) {

        if (Test-Path $p) {

            if ($PSCmdlet.ShouldProcess($p, 'Remove directory')) {

                Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue

            }

        }

    }



    # 6. Remove state keys

    if ($PSCmdlet.ShouldProcess('HKLM:\SOFTWARE\AtlasOS', 'Remove registry tree')) {

        Remove-Item 'HKLM:\SOFTWARE\AtlasOS' -Recurse -Force -ErrorAction SilentlyContinue

    }



    Write-Host ""

    Write-Host "Atlas has been uninstalled. A reboot is strongly recommended." -ForegroundColor Green

    Write-Host "Log saved to $log" -ForegroundColor Cyan

    pause

}

finally {

    Stop-Transcript | Out-Null

}

