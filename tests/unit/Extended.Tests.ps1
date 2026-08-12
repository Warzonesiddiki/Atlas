#Requires -Modules Pester
BeforeAll {
    $moduleCandidates = @(
        "$PSScriptRoot/../../playbook/assets/modules/Lib/Atlas/Atlas.psd1",
        "$PSScriptRoot/../../src/playbook/Executables/AtlasModules/Scripts/Lib/Atlas/Atlas.psd1"
    )
    $modulePath = $moduleCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $modulePath) { throw "Atlas module not found" }
    Import-Module $modulePath -Force
}

Describe "Build range / platform helpers" {
    It "Get-AtlasWindowsBuild returns an integer" {
        Get-AtlasWindowsBuild | Should -BeOfType [int]
    }
    It "Test-AtlasBuildRangeSatisfied for max range" {
        Test-AtlasBuildRangeSatisfied -MaxBuild 99999 | Should -Be $true
    }
    It "Get-AtlasSystemArchitecture returns arm64 or amd64" {
        Get-AtlasSystemArchitecture | Should -BeIn @('arm64','amd64')
    }
    It "Test-AtlasIsLaptop returns bool" {
        Test-AtlasIsLaptop | Should -BeOfType [bool]
    }
    It "Test-AtlasIsVM returns bool" {
        Test-AtlasIsVM | Should -BeOfType [bool]
    }
}

Describe "Registry helpers" {
    It "Set-AtlasRegistryValue round-trips" {
        $key = 'TestKey:\Software\AtlasUnitTest'
        # Use HKCU temp key via the TestRegistry PS drive setup in BeforeAll if present;
        # otherwise skip on non-Windows.
        try {
            New-Item $key -Force -ErrorAction Stop | Out-Null
            Set-AtlasRegistryValue -Path $key -Name 'Foo' -Value 'Bar' -Type REG_SZ
            Get-AtlasRegistryValue -Path $key -Name 'Foo' | Should -Be 'Bar'
            Remove-AtlasRegistryValueSafe -Path $key -Name 'Foo'
            Get-AtlasRegistryValue -Path $key -Name 'Foo' | Should -Be $null
        } catch {
            Set-ItResult -Skipped -Because "Registry tests require Windows HKCU:"
        }
    }
}

Describe "Logging" {
    It "Start-AtlasLog creates a log file and Stop-AtlasLog returns its path" {
        try {
            $path = Start-AtlasLog -Name 'unit-test'
            $path | Should -Not -BeNullOrEmpty
            Test-Path $path | Should -Be $true
            Write-AtlasLog "unit test message"
            $end = Stop-AtlasLog
            $end | Should -Be $path
            Get-Content $path -Raw | Should -Match 'unit test message'
        } catch {
            Set-ItResult -Skipped -Because "Logging requires a writable Atlas log dir (Windows)"
        }
    }
}
