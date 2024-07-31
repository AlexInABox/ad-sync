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
    #. $debugModule -message "User $($userObject.Name) already exists in the Active Directory."
    if ($readOnly) {
        #. $debugModule -message "Would have deleted and recreated user $($userObject.Name) in the Active Directory."
        return
    }
    #Copy old permissions and then delete old user
    $oldUser = (Get-ADUser -Filter "Name -eq '$($userObject.Name)'")
    $oldUserGroups = Get-ADUser -Identity $oldUser.SamAccountName -Properties MemberOf | Select-Object -ExpandProperty MemberOf | Get-ADGroup | Select-Object -ExpandProperty Name
    $oldUserGroups = $oldUserGroups -split " "

    #Delete old user
    #. $debugModule -message "Deleting user $($userObject.Name)"
    Remove-ADUser -Identity $oldUser.SamAccountName -Confirm:$false

    #Recreate user
    #. $debugModule -message "Recreating user $($userObject.Name)"
    ensureOUExists($userObject.path)
    New-ADUser @userObject

    #Add new user to old user groups
    for ($i = 0; $i -lt $oldUserGroups.Length; $i++) {
        #. $debugModule -message "Re-adding user $($userObject.Name) to group $($oldUserGroups[$i])"
        Add-ADGroupMember -Identity $oldUserGroups[$i] -Members $userObject.SamAccountName
    }
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
