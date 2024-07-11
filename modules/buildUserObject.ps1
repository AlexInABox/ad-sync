Param(
    [Parameter(Mandatory = $true)]
    $csvUserLine,

    [Parameter(Mandatory = $true)]
    [string]$configPath,

    [Parameter(Mandatory = $false)]
    [bool]$debugEnabled = 1
)

#Load config values
$configObject = Get-Content -Path $configPath -Raw | ConvertFrom-Json
$parentDN = $configObject.parentDN
[string]$defaultUserPassword = $configObject.defaultUserPassword

function generatePathFromCanonicalName() {
    param (
        [string]$canonicalName
    )

    # Remove the first part (int.polizei.berlin.de/Polizei/)
    $relativePath = $canonicalName -replace "^int\.polizei\.berlin\.de/Polizei/", ""

    # Split the relative path into its components
    $pathComponents = $relativePath -split "/"

    # Remove the last component (USERNAME)
    $pathComponents = $pathComponents[0..($pathComponents.Length - 2)]

    # Construct the DN in reverse order
    $constructedPath = ""
    for ($i = $pathComponents.Length - 1; $i -ge 0; $i--) {
        $constructedPath += "OU=" + $pathComponents[$i] + ","
    }
    $constructedPath += $parentDN

    # Output the constructed DN
    return $constructedPath
}

function buildUserObject() {
    # "Path" entspricht dem Distinguished Name, aber ohne den 'CN=12345678,'-Teil, aka "X.500 OU path"
    # OU=LKA 725,OU=LKA 72,OU=LKA 7,OU=LKA,OU=Dienststellen,OU=Benutzer,OU=ad,DC=msd,DC=polizei,DC=berlin,DC=de
    $path = generatePathFromCanonicalName -canonicalName $csvUserLine.CanonicalName
    $mapID = $csvUserLine.Name
    $samAccountName = "msd$($mapID)"
    $userPrincipalName = "msd$($mapID)@msd.polizei.berlin.de"
    $accountPassword = $(ConvertTo-SecureString $defaultUserPassword -AsPlainText -Force)
    $givenName = $csvUserLine.GivenName
    $surname = $csvUserLine.Surname
    $displayName = "$($givenName) $($surname)"
    $officePhone = $csvUserLine.telephoneNumber #OBS! Get-ADUser uses telephoneNumber, Set-ADUser only knows OfficeTelephone or MobilePhone

    $email = $csvUserLine.Mail
    if ([string]::IsNullOrEmpty($email)) {
        $email = $csvUserLine.UserPrincipalName.Split('@')[0] + "@polizei.berlin.de"
    }

    $newUser = @{
        Path                  = $path
        SamAccountName        = $samAccountName
        UserPrincipalName     = $userPrincipalName
        Enabled               = $true
        ChangePasswordAtLogon = $true
        AccountPassword       = $accountPassword
        Name                  = $mapID
        DisplayName           = $displayName
        GivenName             = $givenName
        Surname               = $surname
        EmailAddress          = $email
        OfficePhone           = $officePhone
    }

    return $newUser
}

return buildUserObject
