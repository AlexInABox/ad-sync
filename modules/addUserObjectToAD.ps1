Param(
    [Parameter(Mandatory = $true)]
    $userObject,

    [Parameter(Mandatory = $true)]
    [string]$configPath,

    [Parameter(Mandatory = $false)]
    [bool]$debugEnabled = 1
)

#Load config values
$configObject = Get-Content -Path $configPath -Raw | ConvertFrom-Json
$debugModule = Join-Path -Path $PSScriptRoot -ChildPath "debug.ps1"

#check if user already exists
###copy group permissions to new userObject
###delete old user
#add user to AD
#maybe: give user group permissions


#Check if all the OUs in the path of a user exist, if not create them
function ensureOUExists {
    param (
        [string]$ouPath
    )
    # Split the OU path into components
    $ouComponents = $ouPath -split ","
    # Starting from the end of the path, check each level (-5 because we dont check the DC's only ON)
    for ($i = ($ouComponents.Length - 5); $i -ge 0; $i--) {
        $ouSubPath = ($ouComponents[$i..($ouComponents.Length - 1)] -join ",")
        # Check if the OU exists
        $ouExists = Get-ADOrganizationalUnit -Filter { DistinguishedName -eq $ouSubPath } -ErrorAction Stop
        if ($ouExists) {
            continue
        }
        # If the OU doesn't exist, create it
        . $debugModule -message "Adding OU to AD: $($ouSubPath)" -debugEnabled $debugEnabled
        New-ADOrganizationalUnit -Name ($ouComponents[$i] -replace "^OU=", "") -Path ($ouComponents[($i + 1)..($ouComponents.Length - 1)] -join ",")
    }
}

function userAlreadyExists {
    $alreadyExists = 1
    $getADUser = (Get-ADUser -Filter "Name -eq '$($userObject.Name)'")
    
    if ($null -eq $getADUser) {
        #Write-Host "Yippie" $userObject.Name "is unique!!"
        $alreadyExists = 0
    }
    return $alreadyExists
}

if (userAlreadyExists) {
    Write-Host "User already exists"
    #TODO: Copy old permissions and then delete old user
}

ensureOUExists($userObject.path)