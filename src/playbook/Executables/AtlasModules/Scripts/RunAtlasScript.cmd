@echo off

:: =============================================================================

:: RunAtlasScript.cmd

::

:: Hardened launcher for all Atlas user-facing scripts.

::   * Auto-elevates if not already admin

::   * Starts a structured Atlas log via Invoke-AtlasScript.ps1

::   * Catches failures and prints the log path

::

:: Existing per-script .cmd files are retained (backwards compat) but are

:: encouraged to delegate here.

:: =============================================================================

setlocal EnableExtensions DisableDelayedExpansion



if "%~1"=="" (

    echo Usage: RunAtlasScript.cmd "<script.ps1>" [args...]

    pause

    exit /b 2

)



:: --- Elevation shim ----------------------------------------------------------

fltmc >nul 2>&1 || (

    set "___args="%~f0" %*"

    powershell -NoP -Command "Start-Process -Verb RunAs -FilePath 'cmd' -ArgumentList '/c call %___args%'" 2>nul

    if errorlevel 1 (

        echo Administrator privileges are required. Re-run as administrator.

        pause

        exit /b 1

    )

    exit /b

)



set "ATLAS_INVOKER=%windir%\AtlasModules\Scripts\Invoke-AtlasScript.ps1"

if not exist "%ATLAS_INVOKER%" (

    echo Atlas modules not found at "%ATLAS_INVOKER%".

    echo Re-run the Atlas playbook or verify the install.

    pause

    exit /b 3

)



powershell -NoP -ExecutionPolicy Bypass -File "%ATLAS_INVOKER%" %*

set "EXIT_CODE=%ERRORLEVEL%"

echo.

if not "%EXIT_CODE%"=="0" pause

exit /b %EXIT_CODE%

