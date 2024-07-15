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

#check if user already exists
###copy group permissions to new userObject
###delete old user
#add user to AD
#maybe: give user group permissions

function userAlreadyExists {
    $alreadyExists = 1
    try {
        Get-ADUser $userObject.Name
    }
    catch {
        Write-Host "Yippie" $userObject.Name "is unique!!"
        $alreadyExists = 0
    }
    return $alreadyExists
}

if (userAlreadyExists) {
    #TODO: Copy old permissions and then delete old user
}