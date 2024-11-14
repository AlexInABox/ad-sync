Param(
    [Parameter(Mandatory = $true)]
    [string]$configPath,

    [Parameter(Mandatory = $false)]
    [bool]$readOnly = 1
)

#import modules
$debugModule = Join-Path -Path $PSScriptRoot -ChildPath "..\debug.ps1"
$fixADModule = Join-Path -Path $PSScriptRoot -ChildPath ".\ad-fix-duplicate-org-groups.ps1"


# date for generating log file name
$date = Get-Date -Format "yyddMM_HHmm"
$foundUsersLogFile = Join-Path -Path $PSScriptRoot -ChildPath "..\..\logs\foundusers_$date.log"
$cleanupCombinedLogFile = Join-Path -Path $PSScriptRoot -ChildPath "..\..\logs\cleanupCombined.log"


$configObject = Get-Content -Path $configPath -Encoding UTF8 | ConvertFrom-Json
#search base ADUsers will be searched in
$searchBase = $configObject.parentDN

#endregion

#delete old combinedLog File
function deleteOldLogFile {
    param($Path)
    if (Test-Path $Path) {
        Remove-Item $Path -Force
    }
    New-Item $Path -ItemType File | Out-Null
}

deleteOldLogFile($cleanupCombinedLogFile)

# print message to console
function printMessage {
    param (
        [string]$message
    )

    Write-Host $message
}

# print message to log file
function printLog {
    param (
        [string]$message
    )

    Add-Content -Path $foundUsersLogFile -Value $message
    Add-Content -Path $cleanupCombinedLogFile -Value $message
    . $debugModule $message
}

# get shortened ldap string for user
function getOUStringOfUser {
    param (
        $user
    )

    $ouComponents = $user.DistinguishedName -split ","
    $ouComponents = $ouComponents[0..($ouComponents.Length - 5)]
    
    return ($ouComponents -join ",")
}

function iterateAD {
    # get all ADUsers
    $users = Get-ADUser -SearchBase $searchBase -Filter *

    $progress = 0
    $foundUsers = 0
    foreach ($user in $users) {
        Write-Progress -Activity "Searching ADUsers... ($($user.Name))" -Status "($progress / $($users.Length)) completed" -PercentComplete $(($progress / $users.Length) * 100)

        # get ADUser groups
        $groups = Get-ADPrincipalGroupMembership -Identity $user
        $organizationGroups = [System.Collections.ArrayList]@()
        foreach ($group in $groups) {
            # check if group starts with 'g-org-' that signals a organization group
            if ($group.Name.StartsWith("g-org-")) {
                [void]$organizationGroups.Add($group.Name)
            }
        }

        # check if user has no g-org group attached
        if ($organizationGroups.count -eq 0) {
            # user has no organization group -> report
            printMessage -message "User '$($user.Name)' has no g-org group attached."

            $foundUsers++

            # print to log
            printLog -message "User '$($user.Name)' has no g-org group attached. (found in: '$(getOUStringOfUser -user $user)"
        }
        # check if user has multiple g-org groups
        elseif ($organizationGroups.count -gt 1) {
            # user has multiple organization groups -> report
            printMessage -message "User '$($user.Name)' has multiple g-org groups attached. ($($organizationGroups))"

            $foundUsers++

            # print all group names to log
            printLog -message "User '$($user.Name)' has multiple g-org groups attached. (found in: '$(getOUStringOfUser -user $user)')"
            foreach ($group in $organizationGroups) {
                printLog -message "$([char]9)- $($group)"
            }
            printLog -message " " #empty line to indicate context ending
        }
        $progress++
    }

    # print amount of found users to console and log
    printMessage -message "`n`n$foundUsers ADUsers with no or multiple organization groups were found. A detailed overview was written to $foundUsersLogFile."
    printLog -message "`n`n$foundUsers ADUsers with no or multiple organization groups were found."
}

. $debugModule -message "Starting to collect users with abnormal org groups."
iterateAD

. $fixADModule -filePath $foundUsersLogFile -readOnly $readOnly