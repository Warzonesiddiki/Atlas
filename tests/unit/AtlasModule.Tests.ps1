#Requires -Modules Pester


<#


.SYNOPSIS


    Unit tests for the Atlas shared module. We mock file system / service /


    registry calls so these tests can run cross-platform in CI.


#>





BeforeAll {


    $moduleCandidates = @(


        "$PSScriptRoot/../../playbook/assets/modules/Lib/Atlas/Atlas.psd1",


        "$PSScriptRoot/../../src/playbook/Executables/AtlasModules/Scripts/Lib/Atlas/Atlas.psd1"


    )


    $modulePath = $moduleCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1


    if (-not $modulePath) { throw "Atlas module not found" }





    Import-Module $modulePath -Force


}





Describe "Module surface" {


    It "exports expected public functions" {


        $expected = @(


            'Write-AtlasLog','Start-AtlasLog','Stop-AtlasLog',


            'Test-AtlasAdmin','Get-AtlasErrorRecord','Invoke-AtlasSafe','Invoke-AtlasLoggedCommand',


            'Test-AtlasTrustedInstaller','Get-AtlasSystemArchitecture',


            'Get-AtlasRegistryValue','Set-AtlasRegistryValue','Remove-AtlasRegistryValueSafe','Test-AtlasRegistryPath',


            'Get-AtlasWindowsDirectory','Get-AtlasModulesDirectory','Get-AtlasDesktopDirectory','Get-AtlasLogDirectory',


            'Get-AtlasFileHash','Compare-AtlasHashTable','Test-AtlasSignature',


            'Test-AtlasYamlPath','Test-AtlasReferencedFiles',


            'Test-AtlasServiceExists','Set-AtlasServiceStart','Backup-AtlasServices','Restore-AtlasServices',


            'Remove-AtlasAppx','Repair-AtlasAppx','Get-AtlasAppxProvisioned',


            'Set-AtlasPolicyValue','Add-AtlasFirewallRule',


            'Test-AtlasIsLaptop','Test-AtlasIsVM','Get-AtlasWindowsBuild','Test-AtlasBuildRangeSatisfied',


            'Write-AtlasHeader','Show-AtlasChoiceMenu','Show-AtlasMessageBox',


            'Get-AtlasState','Test-AtlasTweakApplied','Register-AtlasRollback',


            'Set-AtlasState','Reset-AtlasState','Get-AtlasProfile','Set-AtlasProfile'


        )


        $actual = (Get-Command -Module Atlas | Select-Object -ExpandProperty Name)


        foreach ($fn in $expected) {


            $actual | Should -Contain $fn


        }


    }


}





Describe "Hashing" {


    It "Get-AtlasFileHash returns correct SHA256 for a known file" {


        $f = Join-Path $TestDrive "sample.txt"


        Set-Content -LiteralPath $f -Value "hello atlas" -Encoding ASCII


        # SHA-256 of 'hello atlas\n' (PowerShell adds a trailing newline with Set-Content so we compare via recompute)


        $h = Get-FileHash -LiteralPath $f -Algorithm SHA256


        Get-AtlasFileHash -Path $f | Should -Be $h.Hash.ToUpperInvariant()


    }





    It "Compare-AtlasHashTable detects mismatches and missing files" {


        $f = Join-Path $TestDrive "sample.bin"


        [IO.File]::WriteAllBytes($f, (1..32 | ForEach-Object { 0x41 }))


        $goodHash = Get-AtlasFileHash -Path $f


        $manifest = Join-Path $TestDrive "list.sha256"


        "${goodHash}  sample.bin`n${goodHash}  missing.bin" | Out-File $manifest -Encoding ASCII


        $results = Compare-AtlasHashTable -ManifestPath $manifest -RootPath $TestDrive


        ($results | Where-Object { $_.Path -eq 'sample.bin' }).Status | Should -Be 'Ok'


        ($results | Where-Object { $_.Path -eq 'missing.bin' }).Status | Should -Be 'Missing'


    }


}





Describe "Platform helpers" {


    It "Get-AtlasWindowsBuild returns an integer" {


        $b = Get-AtlasWindowsBuild


        $b | Should -BeOfType [int]


    }


    It "Get-AtlasSystemArchitecture returns arm64 or amd64" {


        Get-AtlasSystemArchitecture | Should -BeIn @('amd64','arm64')


    }


    It "Test-AtlasBuildRangeSatisfied in-range" {


        Test-AtlasBuildRangeSatisfied -MinBuild 1 -MaxBuild 99999 | Should -Be $true


    }


}





Describe "State engine (idempotency)" {


    BeforeAll {


        # Redirect state roots to a temp hive key (reuse pattern from StateEngine.Tests.ps1)


        $testRoot = 'HKCU:\Software\AtlasTest2\State'


        $profKey = 'HKCU:\Software\AtlasTest2\Profile'


        foreach ($k in @($testRoot,$profKey)) {


            if (Test-Path $k) { Remove-Item $k -Recurse -Force }


            New-Item $k -Force | Out-Null


        }


        InModuleScope StateEngine {


            $script:AtlasStateRoot = $testRoot


            $script:AtlasProfileKey = $profKey


        }


    }


    AfterAll {


        Remove-Item 'HKCU:\Software\AtlasTest2' -Recurse -Force


    }


    It "Set-AtlasProfile / Get-AtlasProfile round-trip" {


        Set-AtlasProfile -Profile 'performance'


        Get-AtlasProfile | Should -Be 'performance'


    }


    It "Register-AtlasRollback -> Get-AtlasState retrieves" {


        Register-AtlasRollback -TweakId 'unit.sample' -RevertCommand 'echo r' -Version '1.0' -Category 'test'


        $s = Get-AtlasState -TweakId 'unit.sample'


        $s | Should -Not -BeNullOrEmpty


        $s.Category | Should -Be 'test'


    }


}


