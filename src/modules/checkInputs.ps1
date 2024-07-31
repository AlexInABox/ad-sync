Param(
    [Parameter(Mandatory = $true)]
    [string]$tablePath,

    [Parameter(Mandatory = $true)]
    [string]$configPath
)

#Modules
$debugModule = Join-Path -Path $PSScriptRoot -ChildPath "debug.ps1"

function checkTable {
    param (
        [string]$path
    )

    #Check if file exists
    if (-Not (Test-Path -Path $path -PathType Leaf)) {
        . $debugModule -message "Error: The table does not exist!"
        return $false
    }

    #Check if file has the .csv extension
    $fileExtension = [System.IO.Path]::GetExtension($path)
    if ($fileExtension -ne ".csv") {
        . $debugModule -message "Error: The table is not a CSV file."
        return $false
    }

    return $true
}

function testJSONKey {
    param(
        [psobject]$jsonObject,
        [string]$key
    )

    return $jsonObject.PSObject.Properties.Name -contains $key
}

function checkConfig {
    param (
        [string]$path
    )

    #Check if file exists
    if (-Not (Test-Path -Path $path -PathType Leaf)) {
        . $debugModule -message "Error: The config does not exist!"
        return $false
    }

    #Check if file has the .json extension
    $fileExtension = [System.IO.Path]::GetExtension($path)
    if ($fileExtension -ne ".json") {
        . $debugModule -message "Error: The config is not a JSON file."
        return $false
    } 

    #Check if all keys exist and have proper values
    $requiredKeysInConfig = "csvDelimiter", "maxUsersToProccess", "parentDN", "header", "defaultUserPassword"
    $jsonContent = Get-Content -Path $configPath -Raw
    $jsonObject = $jsonContent | ConvertFrom-Json

    foreach ($key in $requiredKeysInConfig) {
        if (testJSONKey -jsonObject $jsonObject -key $key) {
            . $debugModule -message "Key '$key' exists in the config."
        }
        else {
            . $debugModule -message "Required '$key' does not exist in the config."
            return $false
        }
    }

    return $true
}

return (checkConfig -path $configPath) -and (checkTable -path $tablePath)