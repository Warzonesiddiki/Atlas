#Requires -Modules Pester
<#
  Smoke tests for profile switching and profile-defaults logic.
  These tests do not touch real services/registry; they only verify that the
  script files parse and expose expected parameters/constants.
#>

BeforeAll {
    $scriptsRoot = Join-Path $PSScriptRoot '..' '..' 'src' 'playbook' 'Executables' 'AtlasModules' 'Scripts'
    $setProfile = Join-Path $scriptsRoot 'Set-AtlasProfile.ps1'
}

Describe 'Set-AtlasProfile.ps1' {
    It 'exists in the shipped Scripts directory' {
        Test-Path $setProfile | Should -BeTrue
    }
    It 'declares a -Profile parameter with [ValidateSet] covering all four profiles' {
        $text = Get-Content $setProfile -Raw
        $text | Should -Match '\[ValidateSet\(''balanced'',''performance'',''privacy'',''security''\)\]'
    }
    It 'references the Profile registry key under HKLM:\SOFTWARE\AtlasOS' {
        $text = Get-Content $setProfile -Raw
        $text | Should -Match 'SOFTWARE\\\\AtlasOS\\\\Profile'
    }
}

Describe 'Profile defaults YAML' {
    It 'exists under Configuration/atlas/' {
        $y = Join-Path $PSScriptRoot '..' '..' 'src' 'playbook' 'Configuration' 'atlas' 'profile-defaults.yml'
        Test-Path $y | Should -BeTrue
    }
}
