Param(
    [Parameter(Mandatory = $true)]
    [string]$path,

    [Parameter(Mandatory = $true)]
    [string]$configPath
)

$tmpDirectory = Resolve-Path ".\tmp"

#Load config values
$configObject = Get-Content -Path $configPath -Encoding UTF8 | ConvertFrom-Json
$maxUsersToProccess = $configObject.maxUsersToProccess
$debugModule = Join-Path -Path $PSScriptRoot -ChildPath "debug.ps1"

function createTMP {
    if (-Not (Test-Path -Path $tmpDirectory)) {
        New-Item -ItemType Directory -Path $tmpDirectory
        . $debugModule -message "TMP directory created."
    }    
}
function clearTMP {
    Remove-Item -Path $tmpDirectory"\*"
    . $debugModule -message "TMP directory cleared."
}

function copyTableToTMP {
    param (
        [string]$path
    )

    Copy-Item -path $path -Destination $tmpDirectory
    . $debugModule -message "Copied data to TMP directory."
}

function removeHeaderFromCSV() {
    param (
        [Parameter(Mandatory = $true)]
        [string]$file
    )
   
    if ($maxUsersToProccess -eq 0) {
        $content = Get-Content $file | Select-Object -Skip 1
        . $debugModule -message "No limit on users to process." # revoked commented and changed to debugModule, MRX
    }
    else {
        $content = Get-Content $file | Select-Object -Skip 1 -First $maxUsersToProccess
        . $debugModule -message "Limiting user to process to $maxUsersToProcess." # revoked commented and changed to debugModule, MRX
    }
    # Write the modified content back to the same file, overwriting it
    $content | Set-Content $file
}

#TODO (Betke): Sanitze based on rules or interaction with the user

createTMP
clearTMP
copyTableToTMP -path $path
$fileName = [System.IO.Path]::GetFileName($path)
$tmpFilePath = Join-Path $tmpDirectory $fileName
removeHeaderFromCSV -file $tmpFilePath

return $tmpFilePath