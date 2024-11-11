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
        [string]$path,
        [string]$configPath
    )
    
    # seperator line
    . $debugModule -message " "

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

    # Check if CSV has empty fields (Added, MRX)
    $configObject = Get-Content -Path $configPath -Encoding UTF8 | ConvertFrom-Json
    [char]$delimiter = $configObject.csvDelimiter
    $header = $configObject.header -split $delimiter

    # check content of csv
    $csv = Import-Csv -Path $path -Delimiter $delimiter -Header $header -Encoding UTF8
    $faultFound = $false
    $csv = $csv[1..($csv.Length)]
    $csv | Foreach-Object {
        # check if name is valid (for now: length must be 8 - TODO later: only numbers)
        if (($_.SamAccountName.Length -ne 8) -or ($_.Name.Length -ne 8)) {
            . $debugModule -message "Error: The user $($_.SamAccountName) does not match number pattern."
            $faultFound = $true
        }
        # check if all cells have content in it
        #foreach ($property in $_.psobject.properties) {
        #    if ([string]::IsNullOrWhiteSpace($property.Value)) {
        #        . $debugModule -message "Error: The cell $($property.Name) was empty for $($_.SamAccountName)."
        #        $faultFound = $true
        #    }
        #}
    }
    
    return (-not $faultFound)
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
    $jsonContent = Get-Content -Path $configPath -Raw -Encoding UTF8
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

return (checkConfig -path $configPath) -and (checkTable -path $tablePath -configPath $configPath)