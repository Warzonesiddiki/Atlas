<#
.SYNOPSIS
    Refreshes the pinned SHA-256 hashes (and optionally URLs) for installers
    listed in playbook/assets/modules/Scripts/Installers/versions.json.
    Run this whenever upstream releases a new version of the bundled tools.

.PARAMETER Tool
    Optional: refresh only one tool (e.g. "sysmon"). If omitted, refreshes all.

.PARAMETER OnlyHashes
    If set, only recomputes hashes without bumping URLs.
#>
[CmdletBinding()]
param(
    [string]$Tool,
    [switch]$OnlyHashes
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$versionsPath = Join-Path $PSScriptRoot '../../playbook/assets/modules/Scripts/Installers/versions.json'
$versionsPath = Resolve-Path $versionsPath
$json = Get-Content $versionsPath -Raw | ConvertFrom-Json -AsHashtable

$tmp = Join-Path $env:TEMP ("atlas_bump_" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
    foreach ($topKey in $json.Keys) {
        $entry = $json[$topKey]
        if ($Tool -and $topKey -ne $Tool) {
            # Also iterate "browsers" subkeys
            if ($topKey -eq 'browsers') {
                foreach ($bkey in @($entry.Keys)) {
                    if ($bkey -ne $Tool) { continue }
                }
            } else { continue }
        }
        if ($entry -is [hashtable] -and $entry.ContainsKey('url')) {
            Write-Host "Fetching $topKey..."
            $out = Join-Path $tmp $topKey
            try {
                Invoke-WebRequest -Uri $entry.url -OutFile $out -UseBasicParsing -TimeoutSec 300
                $hash = (Get-FileHash $out -Algorithm SHA256).Hash.ToLowerInvariant()
                $entry.sha256 = $hash
                Write-Host "  -> $hash" -ForegroundColor Green
                if ($entry.ContainsKey('skinUrl')) {
                    $skinOut = Join-Path $tmp ($topKey + '_skin')
                    Invoke-WebRequest -Uri $entry.skinUrl -OutFile $skinOut -UseBasicParsing -TimeoutSec 300
                    $entry.skinSha256 = (Get-FileHash $skinOut -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            } catch {
                Write-Warning "Failed to fetch $($entry.url): $_"
            }
        }
        if ($topKey -eq 'browsers') {
            foreach ($bkey in @($entry.Keys)) {
                if ($Tool -and $bkey -ne $Tool) { continue }
                $be = $entry[$bkey]
                Write-Host "Fetching browser $bkey..."
                $out = Join-Path $tmp "browser_$bkey"
                try {
                    Invoke-WebRequest -Uri $be.url -OutFile $out -UseBasicParsing -TimeoutSec 300
                    $be.sha256 = (Get-FileHash $out -Algorithm SHA256).Hash.ToLowerInvariant()
                    Write-Host "  -> $($be.sha256)" -ForegroundColor Green
                } catch {
                    Write-Warning "Failed fetching $bkey : $_"
                }
            }
        }
    }
    $json | ConvertTo-Json -Depth 6 | Set-Content $versionsPath -Encoding UTF8
    Write-Host "Wrote $versionsPath" -ForegroundColor Green
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
