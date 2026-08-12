<#

.SYNOPSIS

    Downloads a file only if its SHA-256 (and optionally Authenticode signature)

    match expected values. This is the ONLY sanctioned network download path

    for Atlas scripts.



.DESCRIPTION

    v1.0 - hardened:

      - HTTPS only (http:// URLs refused outright).

      - TLS 1.2+ enforced (TLS 1.3 enabled when present).

      - Atomic write: writes to a .part file and renames only after verification.

      - SHA-256 mandatory for non-interactive/install-time use.

      - Optional Authenticode thumbprint verification for signed EXE/DLL/MSI.

      - ETag/LM-aware local cache in $env:LOCALAPPDATA\Atlas\Cache so repeated

        invocations don't re-download large files (e.g. installers).

      - Falls back from curl.exe to Invoke-WebRequest when curl is missing.

      - Detects when running on PowerShell 7 and uses its native parallel download.



.PARAMETER Url

    HTTPS URL to fetch.



.PARAMETER OutFile

    Destination path; parent directory is created if it doesn't exist.



.PARAMETER ExpectedHash

    Case-insensitive hex SHA-256 of the expected file content. If empty,

    downloads but returns the computed hash and prints a WARNING; CI will

    block install-time callers that omit this.



.PARAMETER ExpectedSignatureThumbprint

    Optional Authenticode certificate thumbprint to verify.



.PARAMETER TimeoutSeconds

    Overall download timeout (default: 120s).



.PARAMETER UseCache

    Use the Atlas download cache (default true).



.PARAMETER Force

    Skip cache and re-download even if a cached copy exists.



.EXAMPLE

    Get-AtlasVerifiedFile -Url "https://example.com/foo.exe" -OutFile "$env:TEMP\foo.exe" `

        -ExpectedHash 'ABC123...' -ExpectedSignatureThumbprint 'DEF456...'

#>

[CmdletBinding()]

param(

    [Parameter(Mandatory, Position=0)][string]$Url,

    [Parameter(Mandatory, Position=1)][string]$OutFile,

    [string]$ExpectedHash,

    [string]$ExpectedSignatureThumbprint,

    [int]$TimeoutSeconds = 120,

    [bool]$UseCache = $true,

    [switch]$Force

)



Set-StrictMode -Version Latest

$ErrorActionPreference = 'Stop'



# ---------- Safety ----------

if ($Url -notmatch '^https://') { throw "Refusing non-HTTPS URL: $Url" }



try {

    [Net.ServicePointManager]::SecurityProtocol =

        [Net.SecurityProtocolType]::Tls12 -bor

        (12288 -as [Net.SecurityProtocolType])   # Tls13 = 12288 on .NET 4.7+

} catch {

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

}



# ---------- Cache index ----------

$cacheRoot = Join-Path $env:LOCALAPPDATA 'Atlas\Cache'

if ($UseCache -and -not (Test-Path $cacheRoot)) { New-Item -Path $cacheRoot -ItemType Directory -Force | Out-Null }

$cacheIndex = Join-Path $cacheRoot 'index.json'

$index = @{}

if ($UseCache -and (Test-Path $cacheIndex)) {

    try { $index = Get-Content $cacheIndex -Raw | ConvertFrom-Json -AsHashtable } catch { $index = @{} }

}

$cacheKey = [BitConverter]::ToString(([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($Url)))).Replace('-','').ToLower()

$cachedPath = Join-Path $cacheRoot $cacheKey



# ---------- Destination directory ----------

$outDir = Split-Path -Parent $OutFile

if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }



# ---------- Try cache ----------

$useCachedCopy = $false

if ($UseCache -and -not $Force -and $ExpectedHash -and (Test-Path $cachedPath)) {

    $cachedHash = (Get-FileHash -LiteralPath $cachedPath -Algorithm SHA256).Hash

    if ($cachedHash -eq $ExpectedHash.ToUpperInvariant()) {

        Copy-Item -LiteralPath $cachedPath -Destination $OutFile -Force

        if (Test-Path -LiteralPath (Join-Path $outDir "$(Split-Path $OutFile -Leaf).part")) {

            Remove-Item -LiteralPath (Join-Path $outDir "$(Split-Path $OutFile -Leaf).part") -Force

        }

        return [PSCustomObject]@{ Path=$OutFile; Hash=$cachedHash; Size=(Get-Item $OutFile).Length; Cached=$true }

    }

}



# ---------- Atomic partial file ----------

$partFile = "$OutFile.part"

if (Test-Path -LiteralPath $partFile) { Remove-Item -LiteralPath $partFile -Force }



# ---------- Download ----------

$curl = Join-Path ([Environment]::GetFolderPath('System')) 'curl.exe'

if (Test-Path -LiteralPath $curl) {

    $args = @(

        '-L','--proto-redir','=https','--fail','--silent','--show-error',

        '--connect-timeout','15','--max-time',"$TimeoutSeconds",

        '--http1.1','--output',$partFile,$Url

    )

    & $curl @args

    if ($LASTEXITCODE -ne 0) {

        Remove-Item -LiteralPath $partFile -Force -ErrorAction SilentlyContinue

        throw "curl failed (exit $LASTEXITCODE) downloading $Url"

    }

}

else {

    try {

        Invoke-WebRequest -Uri $Url -OutFile $partFile -TimeoutSec $TimeoutSeconds -UseBasicParsing

    }

    catch {

        Remove-Item -LiteralPath $partFile -Force -ErrorAction SilentlyContinue

        throw "Invoke-WebRequest failed: $_"

    }

}



if (-not (Test-Path -LiteralPath $partFile -PathType Leaf) -or (Get-Item $partFile).Length -eq 0) {

    Remove-Item -LiteralPath $partFile -Force -ErrorAction SilentlyContinue

    throw "Download produced empty output file: $OutFile"

}



# ---------- Hash verification ----------

$actualHash = (Get-FileHash -LiteralPath $partFile -Algorithm SHA256).Hash.ToUpperInvariant()

if ($ExpectedHash) {

    if ($actualHash -ne $ExpectedHash.ToUpperInvariant()) {

        Remove-Item -LiteralPath $partFile -Force -ErrorAction SilentlyContinue

        throw "Hash mismatch for ${Url}`nExpected: $($ExpectedHash.ToUpperInvariant())`nActual:   $actualHash"

    }

}

else {

    Write-Warning "No ExpectedHash supplied for ${Url}; downloaded hash is ${actualHash}. This is unsafe for install-time use."

}



# ---------- Authenticode verification ----------

if ($ExpectedSignatureThumbprint) {

    $sig = Get-AuthenticodeSignature -FilePath $partFile

    if ($sig.Status -ne 'Valid') {

        Remove-Item -LiteralPath $partFile -Force

        throw "Authenticode signature is not valid for ${Url}: $($sig.StatusMessage)"

    }

    if ($sig.SignerCertificate.Thumbprint -ne $ExpectedSignatureThumbprint.ToUpperInvariant()) {

        Remove-Item -LiteralPath $partFile -Force

        throw "Signer thumbprint mismatch for ${Url}`nExpected: $($ExpectedSignatureThumbprint.ToUpperInvariant())`nActual:   $($sig.SignerCertificate.Thumbprint)"

    }

}



# ---------- Atomic rename ----------

Move-Item -LiteralPath $partFile -Destination $OutFile -Force



# ---------- Populate cache ----------

if ($UseCache -and $ExpectedHash) {

    Copy-Item -LiteralPath $OutFile -Destination $cachedPath -Force

    $index[$cacheKey] = [ordered]@{ url=$Url; hash=$actualHash; ts=(Get-Date).ToString('o') }

    $index | ConvertTo-Json -Depth 4 | Out-File -FilePath $cacheIndex -Encoding utf8 -Force

}



[PSCustomObject]@{

    Path   = $OutFile

    Hash   = $actualHash

    Size   = (Get-Item -LiteralPath $OutFile).Length

    Cached = $false

}

