#Requires -RunAsAdministrator


<#


.SYNOPSIS


    Invoker used by RunAtlasScript.cmd.


    This exists only to avoid cmd.exe quoting hell; it loads the Atlas module,


    opens a structured log, runs the target script, and reports errors cleanly.


#>


[CmdletBinding()]


param(


    [Parameter(Mandatory, Position=0)][string]$Script,


    [Parameter(ValueFromRemainingArguments=$true)][string[]]$RemainingArgs


)





Set-StrictMode -Version Latest


$ErrorActionPreference = 'Stop'





$modules = Join-Path ([Environment]::GetFolderPath('Windows')) 'AtlasModules'


Import-Module (Join-Path $modules 'Scripts\Lib\Atlas\Atlas.psd1') -Force





if (-not (Test-Path -LiteralPath $Script -PathType Leaf)) {


    Write-AtlasLog "Target script not found: $Script" 'ERROR'


    throw "Script not found: $Script"


}





$logName = [IO.Path]::GetFileNameWithoutExtension($Script)


Start-AtlasLog -Name $logName | Out-Null


try {


    Write-AtlasLog "Launching $Script"


    & $Script @RemainingArgs


    $code = $LASTEXITCODE


    if ($null -eq $code) { $code = 0 }


    if ($code -eq 0) {


        Write-AtlasLog "Script exited cleanly" 'SUCCESS'


    }


    else {


        Write-AtlasLog "Script exited with code $code" 'ERROR'


    }


    exit $code


}


catch {


    Write-AtlasLog ("Unhandled: " + $_.Exception.Message) 'ERROR'


    if ($_.ScriptStackTrace) {


        Write-AtlasLog $_.ScriptStackTrace 'ERROR'


    }


    exit 1


}


finally {


    $path = Stop-AtlasLog


    if ($LASTEXITCODE -ne 0) {


        Write-Host ""


        Write-Host "Log saved to: $path" -ForegroundColor Yellow


    }


}


