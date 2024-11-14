#region static / configuration variabled

#endregion

# set parameters
param (
    [Parameter(Mandatory = $true)]
    [string]$filePath,

    [Parameter(Mandatory = $false)]
    [bool]$readOnly = 1
)

#Import modules
$debugModule = Join-Path -Path $PSScriptRoot -ChildPath "..\debug.ps1"

$date = Get-Date -Format "yyddMM_HHmm"
$cleanupLogFile = Join-Path -Path $PSScriptRoot -ChildPath "..\..\logs\cleanup_$date.log"

$currentUser = $null
$dn = $null
$groups = [System.Collections.ArrayList]@()

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

    Add-Content -Path $cleanupLogFile -Value $message
    . $debugModule $message
}

function showSelectDialog {
    # display dialog
    $userFullName = $currentUser.givenName + " " + $currentUser.surname
    $userName = $currentUser.Name
    $selectedGroups = $groups | Out-GridView -Title "Select which groups to KEEP for `"$userFullName`" ($userName)" -OutputMode Multiple
    return $selectedGroups
}

function removeUserFromUnselectedGroups {
    param (
        $selectedGroups
    )
    $userName = $currentUser.Name

    #The list is empty when the user dismissed the popup via the "X"
    if ($selectedGroups.count -eq 0) { 
        printMessage "User aborted. Won't remove any group from user '$userName'"
        printLog "User aborted. Won't remove any group from user '$userName'"
        return
    }

    foreach ($group in $selectedGroups) {
        $groups.Remove($group)
    }

    foreach ($group in $groups) {
        # remove user from group
        $userName = $currentUser.Name
        if ($readOnly) {
            printLog "Would remove group '$group' from user '$userName'"
            printMessage  "Would remove group '$group' from user '$userName'"
            continue
        }
        printLog "Removing group '$group' from user '$userName'"
        printMessage  "Removing group '$group' from user '$userName'"
        Remove-ADGroupMember -Identity $group -Members $currentUser -Confirm:$false
    }
}

# Read each line of the file and process it
Get-Content -Path $filePath | ForEach-Object {
    if ($_ -eq " ") {
        # empty line -> script is finished TODO display last elements
        if ($currentUser -ne $null) {
            $selectedGroups = showSelectDialog
            removeUserFromUnselectedGroups $selectedGroups
            $currentUser = $null
            $groups = [System.Collections.ArrayList]@()
        }
    }
    if ($_.StartsWith([char]9)) {
        # add group to user
        [void]$groups.Add($_.Substring(3))
    } 
    if ($_.StartsWith("User")) {
        # set current user string
        $extractedName = $_.Split("'", 3)[1]
        $currentUser = Get-ADUser -Filter "Name -eq '$extractedName'"
    }
}

printLog "Cleanup finished. Log has been written to `"cleanup_$date.log`""
printMessage  "Cleanup finished. Log has been written to `"cleanup_$date.log`""
