#region static / configuration variabled

#endregion

# set parameters
param (
    [Parameter(Mandatory = $true)]
    [string]$filePath,

    [Parameter(Mandatory = $false)]
    [bool]$readOnly = 1
)

$currentUser = $null
$dn = $null
$groups = [System.Collections.ArrayList]@()

function showSelectDialog {
    # display dialog
    $user = Get-ADUser -Identity $currentUser -Properties DisplayName
    $userName = $user.givenName + " " + $user.surname
    $selectedGroups = $groups | Out-GridView -Title "Select which groups to KEEP for `"$userName`" ($currentUser)" -OutputMode Multiple
    return $selectedGroups
}

function removeUserFromGroups {
    param (
        $selectedGroups
    )

    foreach ($group in $selectedGroups) {
        # remove user from group
        $adUser = "msd" + $currentUser
        Write-Host "Would remove group '$group' from user '$currentUser'"
        #Remove-ADGroupMember -Identity $group -Members $adUser
    }
}

# Read each line of the file and process it
Get-Content -Path $filePath | ForEach-Object {
    if ([String]::IsNullOrEmpty($_)) {
        # empty line -> script is finished TODO display last elements
        if ($currentUser -ne $null) {
            $selectedGroups = showSelectDialog
            foreach ($group in $selectedGroups) {
                $groups.Remove($group)
            }
            removeUserFromGroups $groups
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
        $currentUser = $_.Substring(6, 8)
    }
}