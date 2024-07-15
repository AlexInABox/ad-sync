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



#Load config values
$configObject = Get-Content -Path $configPath -Raw | ConvertFrom-Json
[char]$delimiter = $configObject.csvDelimiter
$header = $configObject.header -split $delimiter

#Check if all the OUs in the path of a user exist, if not create them
function ensureOUExists {
    param (
        [string]$ouPath
    )

    # Split the OU path into components
    $ouComponents = $ouPath -split ","

    # Starting from the end of the path, check each level
    for ($i = ($ouComponents.Length - 1); $i -ge 0; $i--) {
        $ouSubPath = ($ouComponents[0..$i] -join ",")
        try {
            # Check if the OU exists
            $ouExists = Get-ADOrganizationalUnit -Filter { DistinguishedName -eq $ouSubPath } -ErrorAction Stop
            if ($ouExists) {
                break
            }
        }
        catch {
            # If the OU doesn't exist, create it
            New-ADOrganizationalUnit -Name ($ouComponents[$i] -replace "^OU=", "") -Path ($ouComponents[($i + 1)..($ouComponents.Length - 1)] -join ",")
        }
    }
}

#Import the CSV file with custom header
$data = Import-Csv -Path $csvPath -Delimiter $delimiter -Header $header -Encoding UTF8

#Add the default password to every user
foreach ($user in $data) {
    #. $buildUserObjectModule -csvUserLine $user -configPath $configPath -debugEnabled $debugEnabled | Format-Table | Out-String | Write-Output
    $userObject = . $buildUserObjectModule -csvUserLine $user -configPath $configPath -debugEnabled $debugEnabled
    if (-Not $debugEnabled) {
        . $addUserObjectToAD -userObject $userObject -configPath $configPath -debugEnabled $debugEnabled
    }


}