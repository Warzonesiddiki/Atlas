<#


.SYNOPSIS


    Lightweight, reproducible benchmark harness for Atlas.





.DESCRIPTION


    Collects metrics that are sensitive to Atlas tweaks:


      - Boot time (from Event Trace log; requires admin)


      - Idle CPU % (10s sample)


      - Idle working set (sum of process WS)


      - Achieved timer resolution (uses MeasureSleep if present)


      - DPC / interrupt time (10s sample via typeperf)


      - Count of running services


    Outputs JSON to stdout or a file and can compare against a baseline.





    This is intentionally conservative: no 3D games, no synthetic benchmarks


    that depend on hardware. It runs in under a minute and surfaces


    regressions from service/policy/timer tweaks.





.PARAMETER BaselinePath


    Optional. Previous JSON output; the script prints DELTA against baseline.





.PARAMETER OutFile


    Write JSON results to this path in addition to stdout.





.EXAMPLE


    pwsh tooling/benchmarks/Run-AtlasBenchmark.ps1 -OutFile before.json


#>


[CmdletBinding()]


param(


    [string]$BaselinePath,


    [string]$OutFile


)





Set-StrictMode -Version Latest


$ErrorActionPreference = 'Continue'





function Get-BootTimeMs {


    try {


        $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime


        # Event ID 100 = Startup processing finished; not present on all editions.


        $ev = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Diagnostics-Performance/Operational';Id=100} -MaxEvents 1 -ErrorAction SilentlyContinue


        if ($ev) {


            $xml = [xml]$ev.ToXml()


            $ms = $xml.Event.UserData.EventXML.BootTime


            if ($ms) { return [int]$ms }


        }


    } catch {}


    $null


}





function Get-TimerResolution {


    $paths = @(


        "$env:windir\AtlasModules\Tools\SetTimerResolution.exe",


        "$env:windir\AtlasDesktop\3. General Configuration\Timer Resolution\! MeasureSleep.exe"


    )


    foreach ($p in $paths) {


        if (Test-Path $p) {


            $out = & $p 2>&1 | Select-Object -First 5


            $m = [regex]::Match($out -join "`n", 'resolution[:\s]+([0-9.]+)\s*ms', 'IgnoreCase')


            if ($m.Success) { return [double]$m.Groups[1].Value }


        }


    }


    $null


}





$results = [ordered]@{


    Timestamp       = (Get-Date).ToString('o')


    Build           = (Get-CimInstance Win32_OperatingSystem).BuildNumber


    Architecture    = ''


    IdleCpuPercent  = $null


    IdlePrivateMB   = $null


    BootTimeMs      = Get-BootTimeMs


    TimerResolution = Get-TimerResolution


    DpcTimePercent  = $null


    InterruptPercent= $null


    RunningServices = 0


}





$arch = (Get-CimInstance Win32_ComputerSystem).SystemType


$results.Architecture = if ($arch -match 'ARM64') { 'arm64' } else { 'amd64' }





# 5s idle sample via typeperf


Write-Host "Sampling idle counters..." -ForegroundColor Cyan


$counters = '\Processor(_Total)\% Processor Time', '\Processor(_Total)\% DPC Time', '\Processor(_Total)\% Interrupt Time'


$sample = Get-Counter -Counter $counters -SampleInterval 1 -MaxSamples 5 -ErrorAction SilentlyContinue


if ($sample) {


    $avg = $sample.CounterSamples | Group-Object Path | ForEach-Object {


        [PSCustomObject]@{ Path = $_.Name; Avg = ($_.Group | Measure-Object -Property CookedValue -Average).Average }


    }


    $results.IdleCpuPercent   = [math]::Round((($avg | Where-Object Path -match 'Processor Time').Avg), 2)


    $results.DpcTimePercent   = [math]::Round((($avg | Where-Object Path -match 'DPC Time').Avg), 2)


    $results.InterruptPercent = [math]::Round((($avg | Where-Object Path -match 'Interrupt Time').Avg), 2)


}





$procs = Get-Process


$results.IdlePrivateMB = [math]::Round((($procs | Measure-Object WorkingSet64 -Sum).Sum / 1MB), 1)


$results.RunningServices = (Get-Service | Where-Object Status -eq Running).Count





$json = $results | ConvertTo-Json -Depth 4


Write-Host $json





if ($OutFile) { $json | Out-File $OutFile -Encoding utf8 }





if ($BaselinePath -and (Test-Path $BaselinePath)) {


    $base = Get-Content $BaselinePath -Raw | ConvertFrom-Json


    Write-Host ""


    Write-Host "Delta vs baseline ($BaselinePath):" -ForegroundColor Cyan


    foreach ($k in $results.Keys) {


        if ($null -eq $results[$k] -or $null -eq $base.$k) { continue }


        if ($results[$k] -is [double] -or $results[$k] -is [int]) {


            $delta = [math]::Round($results[$k] - $base.$k, 2)


            $color = if ($delta -gt 0) { 'Yellow' } elseif ($delta -lt 0) { 'Green' } else { 'Gray' }


            Write-Host ("  {0,-18} {1,10} -> {2,-10}  delta {3:+#.##;-#.##;0}" -f $k, $base.$k, $results[$k], $delta) -ForegroundColor $color


        }


    }


}


