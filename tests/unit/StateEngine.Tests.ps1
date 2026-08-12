#Requires -Modules Pester


<#


.SYNOPSIS


    Unit tests for the Atlas State Engine (StateEngine.psm1).


    Uses a temporary registry drive so tests can run without admin rights to


    HKLM and without touching a real system.


#>





BeforeAll {


    # Load module from the new (relocated) path; also works against old layout


    $moduleCandidates = @(


        "$PSScriptRoot/../../playbook/assets/modules/Lib/Atlas/StateEngine.psm1",


        "$PSScriptRoot/../../src/playbook/Executables/AtlasModules/Scripts/Lib/Atlas/StateEngine.psm1"


    )


    $modulePath = $moduleCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1


    if (-not $modulePath) { throw "StateEngine.psm1 not found" }





    # Load the core Atlas module first for logging helpers (fallback to a


    # minimal stub if not present on the test host).


    $coreCandidates = @(


        "$PSScriptRoot/../../playbook/assets/modules/Lib/Atlas/Atlas.psd1",


        "$PSScriptRoot/../../src/playbook/Executables/AtlasModules/Scripts/Lib/Atlas/Atlas.psd1"


    )


    $corePath = $coreCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1


    if ($corePath) { Import-Module $corePath -Force }





    Import-Module $modulePath -Force





    # Create an isolated test registry key and redirect the engine's root.


    # We inject the private state root via a carefully scoped variable; if


    # that's not possible (private scope) we use a mock.


    $testRoot = 'HKCU:\Software\AtlasTest\State'


    if (-not (Test-Path 'HKCU:\Software\AtlasTest')) { New-Item 'HKCU:\Software\AtlasTest' -Force | Out-Null }


    if (Test-Path $testRoot) { Remove-Item $testRoot -Recurse -Force }


    New-Item $testRoot -Force | Out-Null


    $profileKey = 'HKCU:\Software\AtlasTest\Profile'


    if (Test-Path $profileKey) { Remove-Item $profileKey -Recurse -Force }


    New-Item $profileKey -Force | Out-Null





    # InModuleScope lets us poke the script-scoped variables.


    InModuleScope StateEngine {


        $script:AtlasStateRoot = $testRoot


        $script:AtlasProfileKey = $profileKey


    }


}





AfterAll {


    InModuleScope StateEngine {


        Remove-Item $script:AtlasStateRoot -Recurse -Force -ErrorAction SilentlyContinue


        Remove-Item $script:AtlasProfileKey -Recurse -Force -ErrorAction SilentlyContinue


    }


}





Describe "State Engine basics" {


    It "records a tweak as applied after Register-AtlasRollback" {


        Register-AtlasRollback -TweakId 'test.basic' -RevertCommand 'echo revert' -Version '1.0.0' -Category 'test'


        $s = Get-AtlasState -TweakId 'test.basic'


        $s | Should -Not -BeNullOrEmpty


        $s.Version | Should -Be '1.0.0'


        $s.Category | Should -Be 'test'


        $s.RevertCmd | Should -Be 'echo revert'


    }





    It "skips already-applied tweaks (idempotency)" {


        $script:applyCount = 0


        $apply = {


            $script:applyCount++


            "applied"


        }


        # Use direct script call


        Set-AtlasState -TweakId 'test.idempotent' `


            -ApplyCommand '$script:applyCount++' `


            -RevertCommand 'echo revert' `


            -Version '1.0.0' -Category 'test'


        $script:applyCount | Should -Be 1


        Set-AtlasState -TweakId 'test.idempotent' `


            -ApplyCommand '$script:applyCount++' `


            -RevertCommand 'echo revert' `


            -Version '1.0.0' -Category 'test'


        $script:applyCount | Should -Be 1


    }





    It "re-applies when -Force is given" {


        $script:applyCount = 0


        Set-AtlasState -TweakId 'test.force' -ApplyCommand '$script:applyCount++' -RevertCommand 'echo r' -Version '1.0.0' -Category 'test'


        Set-AtlasState -TweakId 'test.force' -ApplyCommand '$script:applyCount++' -RevertCommand 'echo r' -Version '1.0.0' -Category 'test' -Force


        $script:applyCount | Should -Be 2


    }





    It "re-applies when Version changes" {


        $script:applyCount = 0


        Set-AtlasState -TweakId 'test.ver' -ApplyCommand '$script:applyCount++' -RevertCommand 'echo r' -Version '1.0.0' -Category 'test'


        Set-AtlasState -TweakId 'test.ver' -ApplyCommand '$script:applyCount++' -RevertCommand 'echo r' -Version '1.1.0' -Category 'test'


        $script:applyCount | Should -Be 2


    }





    It "removes state after Reset-AtlasState" {


        Register-AtlasRollback -TweakId 'test.reset' -RevertCommand 'echo r' -Version '1.0' -Category 'test'


        (Get-AtlasState -TweakId 'test.reset') | Should -Not -BeNullOrEmpty


        Reset-AtlasState -TweakId 'test.reset' -Force


        (Get-AtlasState -TweakId 'test.reset') | Should -BeNullOrEmpty


    }





    It "normalize tweak IDs (lowercase, dashes)" {


        Register-AtlasRollback -TweakId 'TEST.UPPER Case!' -RevertCommand 'echo r' -Version '1.0' -Category 'test'


        Get-AtlasState -TweakId 'test-upper-case-' | Should -Not -BeNullOrEmpty


    }





    It "stores and retrieves the current profile" {


        Set-AtlasProfile -Profile 'balanced'


        Get-AtlasProfile | Should -Be 'balanced'


    }


}


