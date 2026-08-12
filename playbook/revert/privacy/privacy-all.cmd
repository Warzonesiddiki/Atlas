@echo off
setlocal
:: Revert privacy/telemetry tweaks. Safe to run.

echo Reverting privacy tweaks...

reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v DisabledByGroupPolicy /f >nul 2>&1

echo Privacy revert complete. Reboot recommended.
pause
exit /b 0
