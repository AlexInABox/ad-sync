Param(
    [Parameter(Mandatory = $true)]
    $userObject,

    [Parameter(Mandatory = $true)]
    [string]$configPath,

    [Parameter(Mandatory = $false)]
    [bool]$readOnly = 1
)

#Get config stuff
$configObject = Get-Content -Path $configPath -Encoding UTF8 | ConvertFrom-Json

#Load modules
$debugModule = Join-Path -Path $PSScriptRoot -ChildPath "debug.ps1"
$statsModule = Join-Path -Path $PSScriptRoot -ChildPath "stats.ps1"

#import-module ActiveDirectory

#Check if all the OUs in the path of a user exist, if not create them
function ensureOUExists {
    param (
        [string]$ouPath
    )

    $listOfAvailableOU = Get-ADOrganizationalUnit -LDAPFilter '(name=*)' -SearchBase $configObject.groupParentDN -SearchScope OneLevel | Select-Object -ExpandProperty Name

    # Split the OU path into components
    $ouComponents = $ouPath -split ","
    $groupOU = ""
    # Starting from the end of the path, check each level (-5 because we dont check the DC's only ON)
    #for ($i = ($ouComponents.Length - 5); $i -ge 0; $i--) {
    for ($i = ($ouComponents.Length - 8); $i -ge 0; $i--) {
        $ouSubPath = ($ouComponents[$i..($ouComponents.Length - 1)] -join ",")
        # Check if the OU exists
        $ouExists = Get-ADOrganizationalUnit -Filter { DistinguishedName -eq $ouSubPath } -ErrorAction Stop

        if ($listOfAvailableOU.Contains(($ouComponents[$i] -replace "^OU=", ""))) {
            $groupOU = "OU=" + $ouComponents[$i] + "," + $configObject.groupParentDN
        }


        $normalizedOUName = (($ouComponents[$i] -replace "^OU=", "").ToLower() -replace " ", "")
        #. $debugModule -message "groupExists: $groupExists ($("g-org-$normalizedOUName"))"
        if ($ouExists) {
            continue
        }

        
        if ($readOnly) {
            . $debugModule -message "Would have created OU: $($ouSubPath)"
            continue
        }
        # If the OU doesn't exist, create it
        . $debugModule -message "Adding OU to AD: $($ouSubPath)"
        New-ADOrganizationalUnit -Name ($ouComponents[$i] -replace "^OU=", "") -Path ($ouComponents[($i + 1)..($ouComponents.Length - 1)] -join ",")
        
    }

    if ($groupOU -eq "") {
        . $debugModule -message "Hierarchical Organization could not be found! ABORT!"
        exit
    }
    
    for ($i = ($ouComponents.Length - 8); $i -ge 0; $i--) {
        $ouSubPath = ($ouComponents[$i..($ouComponents.Length - 1)] -join ",")
        $normalizedOUName = (($ouComponents[$i] -replace "^OU=", "").ToLower() -replace " ", "")
        $groupExists = groupAlreadyExists -name ("g-org-$($normalizedOUName)")

        if ($groupExists) {
            continue
        }

        # Add the new user to their corresponding Security Group
        . $debugModule -message "Adding Security Group"

    


        if ($readOnly) {
            . $debugModule -message "Would have created group: $("g-org-$($normalizedOUName) at $groupOU")" # Added, MRX
            continue
        }

        New-ADGroup -Name ("g-org-$($normalizedOUName)") -GroupScope Global -GroupCategory Security -Path $groupOU
        . $debugModule -message "Group $("g-org-$($normalizedOUName)") was created."
    
        $normalizedParentOUName = (($ouComponents[($i + 1)] -replace "^OU=", "").ToLower() -replace " ", "")
        Add-ADGroupMember -Identity ("g-org-$($normalizedParentOUName)") -Members ("g-org-$($normalizedOUName)")
    }
}

function addUserToOUGroup {
    #Using the userObject path, add the user to the corresponding OU group
    $ouComponents = $userObject.path -split ","
    $normalizedOUName = (($ouComponents[0] -replace "^OU=", "").ToLower() -replace " ", "") #normalize name to lowercase and remove any spaces

    Add-ADGroupMember -Identity ("g-org-$($normalizedOUName)") -Members $userObject.SamAccountName        
}
function groupAlreadyExists {
    param (
        [string]$name
    )
    try {
        $getADGroup = (Get-ADGroup -Identity $name)
        return 1
    } catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        return 0
    }
}
function userAlreadyExists {
    $alreadyExists = 1
    $getADUser = (Get-ADUser -Filter "Name -eq '$($userObject.Name)'")
    
    if ($null -eq $getADUser) {
        $alreadyExists = 0
    }

    return $alreadyExists
}

function updateUserObject {
    param (
        [string]$userGUID
    )
    #Update the user object
    Set-ADUser -Identity $userGUID -GivenName $userObject.GivenName -Surname $userObject.Surname -DisplayName $userObject.DisplayName -EmailAddress $userObject.EmailAddress -OfficePhone $userObject.OfficePhone
}

function moveUserObject {
    param (
        [string]$userGUID
    )
    #Move user to new OU
    Move-ADObject -Identity $userGUID -TargetPath $userObject.path

    # Added, MRX
    # Remove old g-rol groups??? TODO checking! (only for readonly execution for now)
    if ($readOnly) {
        $userGroups = Get-ADPrincipalGroupMembership -Identity $userGUID
        foreach ($group in $groups) {
            if ($group.SamAccountName.StartsWith("g-org-")) {
                #Remove-ADGroupMember -Identity $group -Members $userGUID
                . $debugModule -message "Would have deleted old g-org group $($group.SamAccountName)."
            }
        }
    }
}

. $debugModule -message "Start processing user $($userObject.Name)." # Added, MRX
if (userAlreadyExists) {
    $userGUID = (Get-ADUser -Filter "Name -eq '$($userObject.Name)'").ObjectGUID
    $existingUserPath = (Get-ADUser -Identity $userGUID).DistinguishedName
    $existingUserPath = ($existingUserPath -split ",")
    $first, $rest = $existingUserPath
    $existingUserPath = $rest
    ensureOUExists($userObject.path)
    if (-Not(([string]$existingUserPath) -eq ([string]($userObject.path -split ",")))) {
        if ($readOnly) {
            . $debugModule -message "Would have moved user $($userObject.Name) to OU $($userObject.path)." # Revoked comment, MRX
            return
        }
        moveUserObject -userGUID (Get-ADUser -Filter "Name -eq '$($userObject.Name)'").ObjectGUID
        $userGUID = (Get-ADUser -Filter "Name -eq '$($userObject.Name)'").ObjectGUID
        . $statsModule -moved 1

    } else {
        . $statsModule -updated 1
    }
    if ($readOnly) {
        . $debugModule -message "Would have updated user $($userObject.Name) in the Active Directory." # Revoked comment, MRX
        return
    }
    . $debugModule -message "Updating user $($userObject.Name)." # Added, MRX
    updateUserObject -userGUID $userGUID
    . $debugModule -message "Updated user $($userObject.Name)." # Added, MRX
}
else {
    #Ensure the OU exists
    ensureOUExists($userObject.path)
    if ($readOnly) {
        . $debugModule -message "Would have created user $($userObject.Name) in the Active Directory at path $($userObject.path)." # Revoked comment, MRX
        return
    }
    

    #Create the user
    . $debugModule -message "Creating user $($userObject.Name)." # Revoked comment, MRX
    New-ADUser @userObject
    . $statsModule -created 1
}
#Add user to the OU group
addUserToOUGroup

return $true
