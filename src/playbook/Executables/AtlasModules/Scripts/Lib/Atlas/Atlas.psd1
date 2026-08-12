# Atlas PowerShell Module
#
# A centralized, enterprise-grade library of helpers used by every Atlas script.
# Import with:
#   Import-Module "$env:windir\AtlasModules\Scripts\Lib\Atlas\Atlas.psd1"
#
# Design goals:
#   - Strict mode, explicit errors, no silent failures
#   - Consistent structured logging to file + console
#   - Testable pure functions (no Write-Host side-effects in helpers)
#   - Backwards compatible with the existing AtlasDesktop entry points
#
# License: GPL-3.0-only (same as Atlas)

@{
    RootModule        = 'Atlas.psm1'
    NestedModules     = @('Extended.psm1','StateEngine.psm1')
    ModuleVersion     = '0.7.0'
    GUID              = 'a3d1b0e4-7c44-4b1e-9f66-2a1f3d6c1a7b'
    Author            = 'Atlas Contributors'
    CompanyName       = 'AtlasOS'
    Copyright         = '(c) Atlas Contributors. Licensed under GPL-3.0-only.'
    Description       = 'Shared helpers, logging, diagnostics and safety primitives for AtlasOS.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport = @(
        # Logging
        'Write-AtlasLog', 'Invoke-AtlasLoggedCommand', 'Start-AtlasLog', 'Stop-AtlasLog',
        # Error handling
        'Invoke-AtlasSafe', 'Test-AtlasAdmin', 'Get-AtlasErrorRecord',
        # Elevation / identity
        'Test-AtlasTrustedInstaller', 'Get-AtlasSystemArchitecture',
        # Registry helpers
        'Get-AtlasRegistryValue', 'Set-AtlasRegistryValue', 'Remove-AtlasRegistryValueSafe',
        'Test-AtlasRegistryPath',
        # Paths / environment
        'Get-AtlasWindowsDirectory', 'Get-AtlasModulesDirectory', 'Get-AtlasDesktopDirectory',
        'Get-AtlasLogDirectory',
        # Hashing / integrity
        'Get-AtlasFileHash', 'Compare-AtlasHashTable', 'Test-AtlasSignature',
        # Playbook validation
        'Test-AtlasYamlPath', 'Test-AtlasReferencedFiles',
        # Services
        'Test-AtlasServiceExists','Set-AtlasServiceStart','Backup-AtlasServices','Restore-AtlasServices',
        # AppX
        'Remove-AtlasAppx','Repair-AtlasAppx','Get-AtlasAppxProvisioned',
        # Policy
        'Set-AtlasPolicyValue',
        # Firewall
        'Add-AtlasFirewallRule',
        # Platform detection
        'Test-AtlasIsLaptop','Test-AtlasIsVM','Get-AtlasWindowsBuild','Test-AtlasBuildRangeSatisfied',
        # UI helpers
        'Write-AtlasHeader','Show-AtlasChoiceMenu','Show-AtlasMessageBox',
        # State engine
        'Get-AtlasState','Test-AtlasTweakApplied','Register-AtlasRollback',
        'Set-AtlasState','Reset-AtlasState',
        'Get-AtlasProfile','Set-AtlasProfile'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            ProjectUri = 'https://github.com/Atlas-OS/Atlas'
            LicenseUri = 'https://github.com/Atlas-OS/Atlas/blob/main/LICENSE'
        }
    }
}
