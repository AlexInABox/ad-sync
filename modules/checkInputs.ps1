Param(
    [Parameter(Mandatory = $true)]
    [string]$tablePath,

    [Parameter(Mandatory = $true)]
    [string]$configPath,

    [Parameter(Mandatory = $false)]
    [bool]$debugEnabled = 1
)

#Modules
$debugModule = Join-Path -Path $PSScriptRoot -ChildPath "debug.ps1"

function checkTable {
    param (
        [string]$path
    )

    #Check if file exists
    if (-Not (Test-Path -Path $path -PathType Leaf)) {
        . $debugModule -message "Error: The table does not exist!" -debugEnabled $debugEnabled
        return $false
    }

    #Check if file has the .csv extension
    $fileExtension = [System.IO.Path]::GetExtension($path)
    if ($fileExtension -ne ".csv") {
        . $debugModule -message "Error: The table is not a CSV file." -debugEnabled $debugEnabled
        return $false
    } 

    return $true
}

function checkConfig {
    param (
        [string]$path
    )

    #Check if file exists
    if (-Not (Test-Path -Path $path -PathType Leaf)) {
        . $debugModule -message "Error: The config does not exist!" -debugEnabled $debugEnabled
        return $false
    }

    #Check if file has the .csv extension
    $fileExtension = [System.IO.Path]::GetExtension($path)
    if ($fileExtension -ne ".json") {
        . $debugModule -message "Error: The config is not a JSON file." -debugEnabled $debugEnabled
        return $false
    } 

    return $true
}

return (checkConfig -path $configPath) -and (checkTable -path $tablePath)