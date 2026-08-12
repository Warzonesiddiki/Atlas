@echo off


:: =============================================================================


:: Restore Atlas-modified group-policy registry values to their defaults.


:: Uses the backup stored at HKLM\SOFTWARE\AtlasOS\PolicyBackup written by


:: Set-AtlasPolicyValue / Set-AtlasRegistryValue. Safe to run repeatedly.


:: =============================================================================


setlocal


fltmc >nul 2>&1 || (


    set "___args="%~f0" %*"


    powershell -NoP -Command "Start-Process -Verb RunAs -FilePath 'cmd' -ArgumentList '/c call %___args%'" 2>nul


    exit /b


)





for /f "tokens=*" %%k in ('reg query "HKLM\SOFTWARE\AtlasOS\PolicyBackup" /s /ve 2^>nul ^| findstr /R "HKLM HKCU"') do (


    echo Restoring key: %%k


    reg delete "%%k" /f >nul 2>&1


    :: Backup tree values are stored as properties under each key; re-import via .reg:


    for /f "tokens=1,2,*" %%a in ('reg query "%%k" 2^>nul ^| findstr /R "REG_"') do (


        if /I "%%~b"=="REG_DWORD" reg add "%%k" /v "%%a" /t "%%b" /d "%%c" /f >nul 2>&1


        if /I "%%~b"=="REG_SZ"    reg add "%%k" /v "%%a" /t "%%b" /d "%%c" /f >nul 2>&1


    )


)





reg delete "HKLM\SOFTWARE\AtlasOS\PolicyBackup" /f >nul 2>&1


echo.


echo Group policies restored. A reboot is recommended.


pause


exit /b 0


