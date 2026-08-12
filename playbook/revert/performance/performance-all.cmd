@echo off
setlocal
:: Revert performance tweaks (timer resolution, pagination, core parking)
:: Safe to run even if tweaks weren't applied.

echo Reverting performance tweaks...

reg delete "HKLM\SOFTWARE\AtlasOS\TimerResolution" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v SeparateProcess /f >nul 2>&1

sc config BFE start= auto >nul 2>&1

echo Performance revert complete. Reboot recommended.
pause
exit /b 0
