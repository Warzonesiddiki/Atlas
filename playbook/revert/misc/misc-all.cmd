@echo off
setlocal
:: Revert miscellaneous tweaks.

echo Reverting misc tweaks...

reg delete "HKLM\SOFTWARE\AtlasOS\Misc" /f >nul 2>&1

echo Misc revert complete. Reboot recommended.
pause
exit /b 0
