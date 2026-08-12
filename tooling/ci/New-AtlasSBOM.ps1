<#
.SYNOPSIS
    Emits SBOMs for the Atlas playbook in two standards:
      - CycloneDX 1.4 (JSON) - primary
      - SPDX 2.3 (JSON) - secondary
    Also emits a SHA-256 + SHA-512 manifest for release artifacts.

.PARAMETER PlaybookRoot
    Root of the playbook (auto-detected).

.PARAMETER OutDir
    Where to write the SBOM files (default: playbook/AtlasModules/Other).
#>

[CmdletBinding()]
param(
    [string]$PlaybookRoot,
    [string]$OutDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $PlaybookRoot) {
    $candidate = Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'playbook') -ErrorAction SilentlyContinue
    if (-not $candidate) { $candidate = Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'src' 'playbook') }
    $PlaybookRoot = $candidate
}
if (-not $PlaybookRoot -or -not (Test-Path $PlaybookRoot)) { throw "Could not locate playbook root." }

$binRoot = if (Test-Path (Join-Path $PlaybookRoot 'assets/modules')) { Join-Path $PlaybookRoot 'assets' } else { Join-Path $PlaybookRoot 'Executables' }
if (-not $OutDir) {
    $OutDir = if (Test-Path (Join-Path $PlaybookRoot 'assets/modules/Other')) { Join-Path $PlaybookRoot 'assets/modules/Other' } else { Join-Path $PlaybookRoot 'Executables/AtlasModules/Other' }
}
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$exts = @('.exe','.dll','.zip','.cab','.msi','.msu','.sys','.psm1','.psd1','.ps1','.cmd','.bat')
$files = Get-ChildItem $binRoot -Recurse -File | Where-Object { $exts -contains $_.Extension.ToLowerInvariant() } | Sort-Object FullName

$components = New-Object System.Collections.Generic.List[object]
$spdxPackages = New-Object System.Collections.Generic.List[object]
$spdxRelationships = New-Object System.Collections.Generic.List[object]
$shaManifest = New-Object System.Collections.Generic.List[string]

$root = Join-Path $binRoot ''
foreach ($f in $files) {
    $rel = $f.FullName.Substring($root.Length).Replace('\','/')
    $sha256 = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $sha512 = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA512).Hash.ToLowerInvariant()
    $shaManifest.Add("$sha256  $rel")
    $components.Add([ordered]@{
        type    = 'file'
        name    = $f.Name
        version = (Split-Path $f.DirectoryName -Leaf)
        hashes  = [ordered]@{
            'sha-256' = $sha256
            'sha-512' = $sha512
        }
        size    = $f.Length
    })
    $spdxPackages.Add([ordered]@{
        SPDXID = "SPDXRef-Package-$($f.Name -replace '[^A-Za-z0-9.-]','-')"
        name = $f.Name
        versionInfo = ''
        downloadLocation = 'NOASSERTION'
        filesAnalyzed = $false
        checksums = @(@{ algorithm='SHA256'; checksumValue=$sha256 }, @{ algorithm='SHA512'; checksumValue=$sha512 })
    })
}

# ---- CycloneDX ----
$cyclonedx = [ordered]@{
    bomFormat   = 'CycloneDX'
    specVersion = '1.4'
    serialNumber= 'urn:uuid:' + [guid]::NewGuid().ToString()
    version     = 1
    metadata    = [ordered]@{
        timestamp = (Get-Date).ToString('o')
        tools = @([ordered]@{ vendor='AtlasOS'; name='Atlas'; version='0.7.0' })
        component = [ordered]@{ type='application'; name='Atlas Playbook'; version='0.7.0' }
    }
    components  = @($components)
}
$cyclonedx | ConvertTo-Json -Depth 6 | Out-File (Join-Path $OutDir 'sbom.cyclonedx.json') -Encoding utf8

# ---- SPDX ----
$spdx = [ordered]@{
    spdxVersion = 'SPDX-2.3'
    dataLicense = 'CC0-1.0'
    SPDXID = 'SPDXRef-DOCUMENT'
    name = 'Atlas Playbook'
    documentNamespace = "https://atlasos.net/sbom/$([guid]::NewGuid())"
    creationInfo = [ordered]@{
        created = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
        creators = @('Tool: Atlas SBOM generator 0.7.0', 'Organization: AtlasOS')
        licenseListVersion = '3.22'
    }
    packages = @($spdxPackages)
    relationships = @($spdxRelationships)
}
$spdx | ConvertTo-Json -Depth 8 | Out-File (Join-Path $OutDir 'sbom.spdx.json') -Encoding utf8

# ---- Checksums ----
$shaManifest | Out-File (Join-Path $OutDir 'SHA256SUMS.txt') -Encoding ascii
# SHA-512
$shaManifest512 = New-Object System.Collections.Generic.List[string]
Get-ChildItem $binRoot -Recurse -File | Where-Object { $exts -contains $_.Extension.ToLowerInvariant() } | ForEach-Object {
    $rel = $_.FullName.Substring($root.Length).Replace('\','/')
    $h = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA512).Hash.ToLowerInvariant()
    $shaManifest512.Add("$h  $rel")
}
$shaManifest512 | Out-File (Join-Path $OutDir 'SHA512SUMS.txt') -Encoding ascii

Write-Host ("SBOMs & checksum files written to {0}" -f $OutDir) -ForegroundColor Green
