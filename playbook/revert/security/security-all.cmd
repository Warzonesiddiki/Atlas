@echo off
setlocal
:: Revert security baseline / enterprise / ASR / Sysmon settings.

echo Reverting security tweaks...

reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v EnableLUA /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvancedThreatProtection" /f >nul 2>&1

sc config SysmonLog config= demand >nul 2>&1

echo Security revert complete. Reboot recommended.
pause
exit /b 0
