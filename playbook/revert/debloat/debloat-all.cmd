@echo off
setlocal
:: Revert debloat (AppX removal, component cleanup).
:: Note: CAB-removed components cannot be restored without reinstall media.

echo Reverting debloat (AppX re-provisioning only; CAB removals permanent)...
PowerShell -NoP -Command "Get-AppxPackage -AllUsers * | Foreach { Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml" } 2>$null" >nul 2>&1

echo Debloat revert complete. Reboot recommended.
pause
exit /b 0
