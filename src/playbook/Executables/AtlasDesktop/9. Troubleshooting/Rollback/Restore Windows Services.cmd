@echo off

:: =============================================================================

:: Restores Windows service configuration to the pre-Atlas state captured at

:: install time (from %%windir%%\AtlasModules\Other\winServices.reg).

:: This does NOT fully uninstall Atlas - it only restores services.

:: =============================================================================

setlocal

set "SCRIPT=%windir%\AtlasModules\Scripts\Rollback\Restore-AtlasDefaults.ps1"

if not exist "%SCRIPT%" (

    echo Script not found: "%SCRIPT%"

    echo Ensure Atlas is installed correctly.

    pause

    exit /b 1

)

fltmc >nul 2>&1 || (

    powershell -NoP -Command "Start-Process -Verb RunAs -FilePath 'cmd' -ArgumentList '/c call \"%~f0\" %*'" 2>nul

    exit /b

)

echo This will restore services to their Windows defaults. A reboot will be required.

echo Press Ctrl+C now to cancel, or

pause

powershell -NoP -ExecutionPolicy Bypass -File "%SCRIPT%" -Force

echo.

pause

exit /b %ERRORLEVEL%

