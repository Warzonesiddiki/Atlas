@echo off


:: =============================================================================


:: Restore inbox AppX packages removed by the Atlas playbook (best effort).


:: Re-registers system AppX packages and re-provisions inbox apps from the


:: Windows component store. Some components removed via CAB packages cannot be


:: restored this way - those require in-place repair install.


:: =============================================================================


setlocal


fltmc >nul 2>&1 || (


    set "___args="%~f0" %*"


    powershell -NoP -Command "Start-Process -Verb RunAs -FilePath 'cmd' -ArgumentList '/c call %___args%'" 2>nul


    exit /b


)





echo Re-registering system AppX packages for all users...


powershell -NoP -ExecutionPolicy Bypass -Command ^


  "Get-AppxPackage -AllUsers | Foreach { Add-AppxPackage -DisableDevelopmentMode -Register (Join-Path $_.InstallLocation 'AppxManifest.xml') -ErrorAction SilentlyContinue };"


echo Re-provisioning inbox apps...


powershell -NoP -ExecutionPolicy Bypass -Command ^


  "Get-AppxProvisionedPackage -Online | Where-Object { $_.PackageName -notlike '*Atlas*' } | ForEach-Object { Add-AppxProvisionedPackage -Online -PackagePath $_.PackagePath -LicensePath $_.LicensePath -ErrorAction SilentlyContinue };"


echo.


echo AppX restore attempted. A reboot is recommended.


pause


exit /b 0


