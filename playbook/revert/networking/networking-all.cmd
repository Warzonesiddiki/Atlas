@echo off
setlocal
:: Revert networking hardening tweaks (LLMNR/NBT/SMB1 block)
:: Safe to run even if tweaks weren't applied.

echo Reverting networking hardening...

reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\DNS\Client" /v EnableMulticast /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation" /v EnableSecuritySignature /f >nul 2>&1

sc config lanmanworkstation start= auto >nul 2>&1

echo Networking revert complete. Reboot recommended.
pause
exit /b 0
