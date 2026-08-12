@echo off

:: =============================================================================

:: Revert Atlas gaming tweaks: stop timer resolution task, restore Balanced

:: power plan, remove HAGS registry keys, restore core parking defaults.

:: =============================================================================

setlocal

fltmc >nul 2>&1 || (

    set "___args="%~f0" %*"

    powershell -NoP -Command "Start-Process -Verb RunAs -FilePath 'cmd' -ArgumentList '/c call %___args%'" 2>nul

    exit /b

)



echo Reverting gaming tweaks...



schtasks /delete /tn AtlasTimerResolution /f >nul 2>&1



:: Restore Balanced power plan

powercfg -setactive 381b4222-f694-41f0-9685-ff5bb260df2e >nul 2>&1



reg delete "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v HwSchMode /f >nul 2>&1

reg delete "HKCU\Software\Microsoft\DirectX\UserGpuPreferences" /v SwapEffectUpgradeCache /f >nul 2>&1

reg delete "HKCU\Software\Microsoft\DirectX\GraphicsSettings" /v SwapEffectUpgradeEnable /f >nul 2>&1



:: Restore core parking default (set AC back to default)

powercfg -setacvalueindex scheme_current sub_processor c5449f38-040d-4dcf-9985-e1a8055c6068 100

powercfg -setactive scheme_current

echo Gaming tweaks reverted.

pause

exit /b 0

