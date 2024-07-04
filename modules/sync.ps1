Param(
    [Parameter(Mandatory = $true)]
    [string]$csvPath,

    [Parameter(Mandatory = $true)]
    [string]$configPath,

    [Parameter(Mandatory = $false)]
    [bool]$debugEnabled = 1
)

#Load config values
$configObject = Get-Content -Path $configPath -Raw | ConvertFrom-Json
[char]$delimiter = $configObject.csvDelimiter
$maxUsersToProccess = $configObject.maxUsersToProccess
$header = $configObject.header -split $delimiter
[string]$defaultUserPassword = $configObject.defaultUserPassword

function removeHeaderFromCSV() {
    param (
        [Parameter(Mandatory = $true)]
        [string]$file
    )
   
    if ($maxUsersToProccess -eq 0) {
        $content = Get-Content $file | Select-Object -Skip 1
    } else {
        $content = Get-Content $file | Select-Object -Skip 1 -First $maxUsersToProccess
    }
    # Write the modified content back to the same file, overwriting it
    $content | Set-Content $file
}

#Remove the header
removeHeaderFromCSV -file $csvPath

$data = Import-Csv -Path $csvPath -Delimiter $delimiter -Header $header -Encoding UTF8

Write-Host $data