Param(
    [Parameter(Mandatory = $true)]
    [string]$csvPath,

    [Parameter(Mandatory = $true)]
    [string]$configPath,

    [Parameter(Mandatory = $false)]
    [bool]$debugEnabled = 1
)

#Import modules
#import-module ActiveDirectory
$buildUserObjectModule = Join-Path -Path $PSScriptRoot -ChildPath "buildUserObject.ps1"
$addUserObjectToAD = Join-Path -Path $PSScriptRoot -ChildPath "addUserObjectToAD.ps1"
$debugModule = Join-Path -Path $PSScriptRoot -ChildPath "debug.ps1"



#Load config values
$configObject = Get-Content -Path $configPath -Raw | ConvertFrom-Json
[char]$delimiter = $configObject.csvDelimiter
$header = $configObject.header -split $delimiter

#Import the CSV file with custom header
$data = Import-Csv -Path $csvPath -Delimiter $delimiter -Header $header -Encoding UTF8

$processedUserCount = 0
$reportProcessedUserCountInterval = [int]($data.Length / 50)
if ($reportProcessedUserCountInterval -eq 0){
    $reportProcessedUserCountInterval = 1
}
foreach ($user in $data) {
    if  (-Not ($processedUserCount % $reportProcessedUserCountInterval) -Or ($processedUserCount -eq $data.Length - 1)) {
        Write-Host "Processed $($processedUserCount)/$($data.Length) users."
    }
    #. $buildUserObjectModule -csvUserLine $user -configPath $configPath -debugEnabled $debugEnabled | Format-Table | Out-String | Write-Output
    $userObject = . $buildUserObjectModule -csvUserLine $user -configPath $configPath -debugEnabled $debugEnabled
    if (-Not $debugEnabled) {
        . $addUserObjectToAD -userObject $userObject -configPath $configPath -debugEnabled $debugEnabled
    }
    $processedUserCount++

}