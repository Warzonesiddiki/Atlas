@echo off
:: Wrapper for Set-AtlasProfile.ps1 — launched from the AtlasDesktop folder.
setlocal
set "___args=%~f0 %*"
fltmc >nul 2>&1 || (
    echo Administrator privileges are required.
    powershell -c "Start-Process -Verb RunAs -FilePath 'powershell.exe' -ArgumentList '-NoP -NonI -ExecutionPolicy Bypass -File ""%windir%\AtlasModules\Scripts\Set-AtlasProfile.ps1""'" 2>nul || (
        echo You must run this script as admin.
        if "%*"=="" pause
        exit /b 1
    )
    exit /b
)
powershell -NoP -NonI -ExecutionPolicy Bypass -File "%windir%\AtlasModules\Scripts\Set-AtlasProfile.ps1" %*
endlocal
