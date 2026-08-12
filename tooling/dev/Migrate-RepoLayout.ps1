<#

.SYNOPSIS

    One-time migration script to move the repository from the legacy layout

    (src/playbook, src/sxsc, src/release-zip, scripts/) into the final

    v1.0 layout (playbook/, packages/, tooling/, tests/, i18n/, docs/).



.DESCRIPTION

    Running this script is IDEMPOTENT. It:

      1. Creates any missing target directories.

      2. Moves files that have not yet been moved.

      3. Rewrites path references in YAML/PS1/CMD/MD/JSON/conf/sh files.

      4. Removes the old empty directories after migration completes.



    After migration, run:

        pwsh tooling/ci/Validate-AtlasPlaybook.ps1 -Strict



.NOTES

    Back up your repo or commit before running this. It touches hundreds of files.

    On failure you can `git reset --hard` back.

#>



[CmdletBinding(SupportsShouldProcess)]

param(

    [switch]$Force

)



Set-StrictMode -Version Latest

$ErrorActionPreference = 'Stop'



$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..' '..')

Push-Location $repoRoot

try {

    # ---- 1. Directory map (old -> new) --------------------------------------

    $dirMap = [ordered]@{

        'src/playbook/Configuration'          = 'playbook/core/legacy'   # contents re-sorted by a later pass

        'src/playbook/Executables/AtlasModules'= 'playbook/assets/modules'

        'src/playbook/Executables/AtlasDesktop'= 'playbook/assets/desktop'

        'src/playbook/Executables/Themes'      = 'playbook/assets/themes'

        'src/playbook/Executables/Images'      = 'playbook/assets/images'

        'src/sxsc'                              = 'packages/legacy'

        'src/sxsc-disabled'                     = 'packages/legacy-disabled'

        'src/release-zip'                       = 'playbook/release'

        'src/dependencies'                      = 'dependencies'

        'scripts/ci'                            = 'tooling/ci'

        'scripts/dev'                           = 'tooling/dev'

    }



    # Top-level files to move

    $fileMap = [ordered]@{

        'src/playbook/playbook.conf'     = 'playbook/playbook.conf'

        'src/playbook/playbook.png'      = 'playbook/playbook.png'

        'src/playbook/build-playbook.cmd'= 'tooling/dev/build-playbook.cmd'

        'src/playbook/build-playbook.sh' = 'tooling/dev/build-playbook.sh'

        'src/README.md'                  = 'docs/legacy-src-readme.md'

    }



    foreach ($target in ($dirMap.Values + $fileMap.Values | Split-Path -Parent | Sort-Object -Unique)) {

        $t = Join-Path $repoRoot $target

        if (-not (Test-Path $t)) { New-Item -ItemType Directory -Path $t -Force | Out-Null }

    }



    # ---- 2. String replacements (run BEFORE moving so we don't lose originals)

    $replacements = [ordered]@{

        'src/playbook/Configuration'     = 'playbook/core'

        'src/playbook/Executables/AtlasModules' = 'playbook/assets/modules'

        'src/playbook/Executables/AtlasDesktop' = 'playbook/assets/desktop'

        'src/playbook/Executables/Themes'= 'playbook/assets/themes'

        'src/playbook/Executables/Images'= 'playbook/assets/images'

        'src/sxsc/'                      = 'packages/'

        'src/release-zip/'               = 'playbook/release/'

        'scripts/ci/'                    = 'tooling/ci/'

        'scripts/dev/'                   = 'tooling/dev/'

        'Configuration/atlas/'           = 'core/'

        'Executables/AtlasModules/'      = 'assets/modules/'

        'Executables/AtlasDesktop/'      = 'assets/desktop/'

    }



    $filesToPatch = Get-ChildItem -Path $repoRoot -Recurse -File `

        -Include *.yml,*.yaml,*.ps1,*.psm1,*.psd1,*.cmd,*.bat,*.sh,*.md,*.json,*.conf |

        Where-Object { $_.FullName -notmatch [regex]::Escape((Join-Path $repoRoot '.git')) }



    $patched = 0

    foreach ($f in $filesToPatch) {

        $content = Get-Content -LiteralPath $f.FullName -Raw

        $newContent = $content

        foreach ($k in $replacements.Keys) {

            $newContent = $newContent -replace [regex]::Escape($k), $replacements[$k]

        }

        if ($newContent -ne $content) {

            if ($PSCmdlet.ShouldProcess($f.FullName, "Rewrite path references")) {

                Set-Content -LiteralPath $f.FullName -Value $newContent -Encoding UTF8

            }

            $patched++

        }

    }

    Write-Host ("Patched {0} files." -f $patched) -ForegroundColor Cyan



    # ---- 3. Move directories (only if target is empty) ----------------------

    foreach ($old in $dirMap.Keys) {

        $oldAbs = Join-Path $repoRoot $old

        $newAbs = Join-Path $repoRoot $dirMap[$old]

        if (-not (Test-Path $oldAbs)) { continue }

        $items = Get-ChildItem -LiteralPath $oldAbs -Force

        foreach ($item in $items) {

            $dest = Join-Path $newAbs $item.Name

            if (Test-Path $dest) {

                Write-Host "  skip   $($item.Name) (already exists in target)" -ForegroundColor DarkGray

                continue

            }

            if ($PSCmdlet.ShouldProcess($item.FullName, "Move to $dest")) {

                Move-Item -LiteralPath $item.FullName -Destination $dest -Force

            }

        }

        if (-not (Get-ChildItem -LiteralPath $oldAbs -Force -ErrorAction SilentlyContinue)) {

            Remove-Item -LiteralPath $oldAbs -Force -Recurse -ErrorAction SilentlyContinue

        }

    }

    foreach ($old in $fileMap.Keys) {

        $oldAbs = Join-Path $repoRoot $old

        $newAbs = Join-Path $repoRoot $fileMap[$old]

        if ((Test-Path $oldAbs) -and -not (Test-Path $newAbs)) {

            if ($PSCmdlet.ShouldProcess($oldAbs, "Move to $newAbs")) { Move-Item $oldAbs $newAbs -Force }

        }

    }



    # ---- 4. Clean up old src/ tree if empty ---------------------------------

    if (Test-Path (Join-Path $repoRoot 'src')) {

        $remaining = Get-ChildItem (Join-Path $repoRoot 'src') -Recurse -Force -ErrorAction SilentlyContinue

        if (-not $remaining) {

            if ($PSCmdlet.ShouldProcess('src/', 'Remove empty legacy directory')) {

                Remove-Item (Join-Path $repoRoot 'src') -Recurse -Force

            }

            Write-Host "Removed empty src/ tree." -ForegroundColor Green

        }

        else {

            Write-Warning "src/ still contains files; manual review required:"

            $remaining | Select-Object FullName

        }

    }



    Write-Host ""

    Write-Host "Migration complete. Run the validator now:" -ForegroundColor Green

    Write-Host "  pwsh tooling/ci/Validate-AtlasPlaybook.ps1 -Strict" -ForegroundColor Cyan

}

finally {

    Pop-Location

}

