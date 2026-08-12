@echo off

:: =============================================================================

:: Revert all Atlas AI-feature tweaks. Safe to run even if features weren't

:: installed (policy keys just get deleted).

:: =============================================================================

setlocal

fltmc >nul 2>&1 || (

    set "___args="%~f0" %*"

    powershell -NoP -Command "Start-Process -Verb RunAs -FilePath 'cmd' -ArgumentList '/c call %___args%'" 2>nul

    exit /b

)



echo Reverting AI-feature policies...



for %%k in (

    "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"

    "HKCU\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"

    "HKCU\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"

    "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"

    "HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer"

    "HKLM\SOFTWARE\Policies\Microsoft\PaintStudio"

) do (

    reg delete %%k /f >nul 2>&1

)



reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowCopilotButton /f >nul 2>&1

reg delete "HKCU\Software\Microsoft\Windows\Shell\Copilot" /v IsCopilotAvailable /f >nul 2>&1



for %%s in (RecallService AIFabricSvc WindowsAIFabric AIFabric) do (

    sc config %%s start= demand >nul 2>&1

)



echo AI features reverted. A reboot is recommended.

pause

exit /b 0

