<#


.SYNOPSIS


    Signs an Atlas release artifact (APBX, zip, scripts) with a code-signing


    certificate and produces detached signature + checksum files.





.DESCRIPTION


    Uses either Authenticode (for .ps1/.psm1/.psd1/.cmd/.exe/.dll/.msi) or


    GPG/PGP detached signatures (for .apbx, .zip, SBOMs, checksum files) so


    end users can verify releases.





.PARAMETER Path


    File or directory to sign. If a directory is provided, all eligible files


    within are signed.





.PARAMETER CertificateThumbprint


    Thumbprint of a code-signing cert in Cert:\CurrentUser\My. For releases


    this should be an EV cert stored on a hardware token.





.PARAMETER GpgKeyId


    GPG key ID used for detached signatures of archive artifacts. If not


    specified, GPG signing is skipped.





.PARAMETER OutputDir


    Directory to place signed artifacts + .sig / checksum files. Defaults to


    a "signed" folder next to the input.


#>


[CmdletBinding()]


param(


    [Parameter(Mandatory, Position=0)][string]$Path,


    [string]$CertificateThumbprint,


    [string]$GpgKeyId,


    [string]$OutputDir


)





Set-StrictMode -Version Latest


$ErrorActionPreference = 'Stop'





if (-not (Test-Path $Path)) { throw "Path not found: $Path" }


$targets = if ((Get-Item $Path).PSIsContainer) {


    Get-ChildItem $Path -Recurse -File


} else { Get-Item $Path }





if (-not $OutputDir) { $OutputDir = Join-Path (Split-Path $Path -Parent) 'signed' }


New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null





$authenticodeExts = @('.exe','.dll','.msi','.ps1','.psm1','.psd1','.cmd','.bat','.cab')


$detachedExts = @('.apbx','.zip','.json','.txt','.sha256','.sha512')





foreach ($f in $targets) {


    Copy-Item $f.FullName -Destination $OutputDir -Force


    $out = Join-Path $OutputDir $f.Name


    if ($CertificateThumbprint -and $authenticodeExts -contains $f.Extension.ToLower()) {


        Set-AuthenticodeSignature -FilePath $out -Certificate (Get-Item "Cert:\CurrentUser\My\$CertificateThumbprint") -TimestampServer 'http://timestamp.digicert.com' | Out-Null


        Write-Host "Signed (Authenticode): $($f.Name)" -ForegroundColor Green


    }


    if ($GpgKeyId -and ($detachedExts -contains $f.Extension.ToLower() -or $f.Name -like 'SHA*SUMS*')) {


        $sigPath = "$out.sig"


        if (Get-Command gpg -ErrorAction SilentlyContinue) {


            & gpg --batch --yes --detach-sign --armor --local-user $GpgKeyId --output $sigPath $out *> $null


            if ($LASTEXITCODE -eq 0) { Write-Host "Signed (GPG): $($f.Name)" -ForegroundColor Green }


            else { Write-Warning "gpg signing failed for $($f.Name)" }


        } else {


            Write-Warning "gpg not on PATH; skipping detached signature for $($f.Name)"


        }


    }


}





# Generate SHA256/SHA512 for all signed output


$manifest256 = Join-Path $OutputDir 'SHA256SUMS.txt'


$manifest512 = Join-Path $OutputDir 'SHA512SUMS.txt'


Push-Location $OutputDir


try {


    Get-ChildItem -File -Exclude 'SHA*SUMS*','*.sig' | ForEach-Object {


        "{0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower(), $_.Name


    } | Out-File $manifest256 -Encoding ascii


    Get-ChildItem -File -Exclude 'SHA*SUMS*','*.sig' | ForEach-Object {


        "{0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA512).Hash.ToLower(), $_.Name


    } | Out-File $manifest512 -Encoding ascii


    Write-Host "Checksums written to $OutputDir"


} finally { Pop-Location }


