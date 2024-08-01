Param(
    [Parameter(Mandatory = $true)]
    $userObject,

    [Parameter(Mandatory = $true)]
    [string]$configPath,

    [Parameter(Mandatory = $false)]
    [bool]$readOnly = 1
)

#Load modules
$debugModule = Join-Path -Path $PSScriptRoot -ChildPath "debug.ps1"

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
        if ($readOnly) {
            #Write-Host "Would have created OU: $($ouSubPath)"
            continue
        }
        # If the OU doesn't exist, create it
        . $debugModule -message "Adding OU to AD: $($ouSubPath)"
        New-ADOrganizationalUnit -Name ($ouComponents[$i] -replace "^OU=", "") -Path ($ouComponents[($i + 1)..($ouComponents.Length - 1)] -join ",")
        # Create a security group inside that OU and add it as a member of that one above
        . $debugModule -message "Adding Security Group"
        $normalizedOUName = (($ouComponents[$i] -replace "^OU=", "").ToLower() -replace " ", "") #normalize name to lowercase and remove any spaces
        $normalizedParentOUName = (($ouComponents[($i + 1)] -replace "^OU=", "").ToLower() -replace " ", "")

        New-ADGroup -Name ("g-org-$($normalizedOUName)") -GroupScope Global -GroupCategory Security -Path ($ouComponents[($i)..($ouComponents.Length - 1)] -join ",")
        Add-ADGroupMember -Identity ("g-org-$($normalizedParentOUName)") -Members ("g-org-$($normalizedOUName)")
    }
}

function addUserToOUGroup {
    #Using the userObject path, add the user to the corresponding OU group
    $ouComponents = $userObject.path -split ","
    $normalizedOUName = (($ouComponents[0] -replace "^OU=", "").ToLower() -replace " ", "") #normalize name to lowercase and remove any spaces

    Add-ADGroupMember -Identity ("g-org-$($normalizedOUName)") -Members $userObject.SamAccountName        
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
    $userGUID = (Get-ADUser -Filter "Name -eq '$($userObject.Name)'").ObjectGUID
    #. $debugModule -message $userGUID
    $existingUserPath = (Get-ADUser -Identity $userGUID).DistinguishedName
    $existingUserPath = ($existingUserPath -split ",")
    $first, $rest = $existingUserPath
    $existingUserPath = $rest
    if (-Not(([string]$existingUserPath) -eq ([string]($userObject.path -split ",")))) {
        #. $debugModule -message "User $($userObject.Name) already exists in the correct OU."
        . $statsModule -moved 1
        if ($readOnly) {
            #. $debugModule -message "Would have moved user $($userObject.Name) to OU $($userObject.path)."
            return
        }
        ensureOUExists($userObject.path)
        moveUserObject -userGUID (Get-ADUser -Filter "Name -eq '$($userObject.Name)'").ObjectGUID
        $userGUID = (Get-ADUser -Filter "Name -eq '$($userObject.Name)'").ObjectGUID
        #. $debugModule -message $userGUID
    } else {
        . $statsModule -updated 1
    }
    if ($readOnly) {
        #. $debugModule -message "Would have updated user $($userObject.Name) in the Active Directory."
        return
    }
    updateUserObject -userGUID $userGUID
}
else {
    if ($readOnly) {
        #. $debugModule -message "Would have created user $($userObject.Name) in the Active Directory."
        return
    }
    #Ensure the OU exists
    ensureOUExists($userObject.path)

    #Create the user
    #. $debugModule -message "Creating user $($userObject.Name)"
    New-ADUser @userObject
}
#Add user to the OU group
addUserToOUGroup

return
