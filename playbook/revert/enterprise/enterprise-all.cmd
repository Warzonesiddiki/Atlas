@echo off

:: =============================================================================

:: Revert enterprise/security baseline tweaks (LSA, LM hash, SMB1, ASR, BitLocker task).

:: Re-installs SMBv1 if it was disabled (for legacy network shares).

:: Does NOT remove Sysmon (do that separately via sysmon -u).

:: =============================================================================

setlocal

fltmc >nul 2>&1 || (

    set "___args="%~f0" %*"

    powershell -NoP -Command "Start-Process -Verb RunAs -FilePath 'cmd' -ArgumentList '/c call %___args%'" 2>nul

    exit /b

)



echo Reverting enterprise baselines...

reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v RunAsPPL /f >nul 2>&1

reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v RunAsPPLBoot /f >nul 2>&1

reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v NoLMHash /f >nul 2>&1



:: Enable SMB1 again (if user wants it)

powershell -NoP -Command "Enable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue" >nul 2>&1



:: Reset ASR rules to not configured (best-effort)

powershell -NoP -Command "try { $ids=@('56a863a9-875e-4185-98a7-b882c64b5ce5','7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c','d4f940ab-401b-4efc-aadc-ad5f3c50688a','75668c1f-73b5-4cf0-93b0-fc75ef9d2b95','92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b','5beb7efe-fd9a-4556-801d-275e5ffc04cc','be9ba2d9-53ea-4cdc-84e5-9b1eeee46550','9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2','d1e49aac-8f56-4280-b9ba-993a6d77406c','b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4'); foreach ($id in $ids) { Remove-MpPreference -AttackSurfaceReductionRules_Ids $id -ErrorAction SilentlyContinue } } catch {}"

schtasks /delete /tn AtlasBitLockerPrompt /f >nul 2>&1

echo Enterprise baseline tweaks reverted.

pause

exit /b 0

