Param(
    [Parameter(Mandatory = $true)]
    [string]$path,

    [Parameter(Mandatory = $true)]
    [string]$configPath,

    [Parameter(Mandatory = $false)]
    [bool]$debugEnabled = 1
)

$tmpDirectory = Resolve-Path ".\tmp"

#Load config values
$configObject = Get-Content -Path $configPath -Raw | ConvertFrom-Json
$maxUsersToProccess = $configObject.maxUsersToProccess

function clearTMP {
    Remove-Item -Path $tmpDirectory"\*"
}
function copyTableToTMP {
    param (
        [string]$path
    )

    Copy-Item -path $path -Destination $tmpDirectory
}

function removeHeaderFromCSV() {
    param (
        [Parameter(Mandatory = $true)]
        [string]$file
    )
   
    if ($maxUsersToProccess -eq 0) {
        $content = Get-Content $file | Select-Object -Skip 1
    }
    else {
        $content = Get-Content $file | Select-Object -Skip 1 -First $maxUsersToProccess
    }
    # Write the modified content back to the same file, overwriting it
    $content | Set-Content $file
}

#TODO: Sanitze based on rules or interaction with the user

clearTMP
copyTableToTMP -path $path
$fileName = [System.IO.Path]::GetFileName($path)
$tmpFilePath = Join-Path $tmpDirectory $fileName
removeHeaderFromCSV -file $tmpFilePath

return $tmpFilePath