@echo off

:: Revert Atlas "Disable Windows Recall" tweak.

:: Re-enables the AI policies (user can manually re-enable the optional feature

:: via Settings if desired).

fltmc >nul 2>&1 || (

    powershell -NoP -Command "Start-Process -Verb RunAs -FilePath 'cmd' -ArgumentList '/c call \"%~f0\"'" 2>nul

    exit /b

)

reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v AllowRecallEnablement /f >nul 2>&1

reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v DisableAIDataAnalysis /f >nul 2>&1

reg delete "HKCU\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v AllowRecallEnablement /f >nul 2>&1

reg delete "HKCU\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v DisableAIDataAnalysis /f >nul 2>&1

for %%s in (RecallService AIFabricSvc WindowsAIFabric AIFabric) do (

    sc config %%s start= demand >nul 2>&1

)

echo Windows Recall policies reverted. You may re-enable the optional feature via Settings.

pause

exit /b 0

