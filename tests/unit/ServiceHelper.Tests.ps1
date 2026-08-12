#Requires -Modules Pester
<#
  Unit tests for Extended.psm1 service/policy/AppX helpers.
  These tests mock out all external calls (no real service/reg changes),
  so they can run on any host including CI on Linux (with the module stubbed).
#>

BeforeAll {
    $moduleRoot = Join-Path $PSScriptRoot '..' '..' 'playbook' 'assets' 'modules' 'Lib' 'Atlas'
    Import-Module (Join-Path $moduleRoot 'Atlas.psd1') -Force -ErrorAction SilentlyContinue
}

Describe 'Set-AtlasServiceStart helper contracts' {
    It 'exports Set-AtlasServiceStart / Backup-AtlasServices / Restore-AtlasServices' {
        Get-Command Set-AtlasServiceStart -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Get-Command Backup-AtlasServices -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Get-Command Restore-AtlasServices -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}

Describe 'Set-AtlasPolicyValue helper contracts' {
    It 'exports Set-AtlasPolicyValue' {
        Get-Command Set-AtlasPolicyValue -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}

Describe 'Add-AtlasFirewallRule helper contracts' {
    It 'exports Add-AtlasFirewallRule' {
        Get-Command Add-AtlasFirewallRule -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}

Describe 'Platform detection helpers' {
    It 'Test-AtlasIsLaptop returns a boolean (mocked)' {
        Mock Get-CimInstance { return [PSCustomObject]@{ PCSystemType = 1 } } -ModuleName Atlas
        # Function exists; smoke-test returns bool
        (Test-AtlasIsLaptop -ErrorAction SilentlyContinue).GetType().Name | Should -BeIn @('Boolean','bool')
    }
    It 'Get-AtlasWindowsBuild returns an integer' {
        Mock Get-CimInstance { return [PSCustomObject]@{ BuildNumber = '26100' } } -ModuleName Atlas
        [int](Get-AtlasWindowsBuild -ErrorAction SilentlyContinue) | Should -Be 26100
    }
}

Describe 'Test-AtlasBuildRangeSatisfied' {
    It 'returns true for a build inside [min,max]' {
        Test-AtlasBuildRangeSatisfied -Build 26100 -MinBuild 22000 -MaxBuild 99999 -ErrorAction SilentlyContinue | Should -BeTrue
    }
    It 'returns false for a build below min' {
        Test-AtlasBuildRangeSatisfied -Build 19000 -MinBuild 22000 -ErrorAction SilentlyContinue | Should -BeFalse
    }
}
