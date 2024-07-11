Param(
    [Parameter(Mandatory = $true)]
    [string]$csvPath,

    [Parameter(Mandatory = $true)]
    [string]$configPath,

    [Parameter(Mandatory = $false)]
    [bool]$debugEnabled = 1
)

#import-module ActiveDirectory

#Load config values
$configObject = Get-Content -Path $configPath -Raw | ConvertFrom-Json
[char]$delimiter = $configObject.csvDelimiter
$parentDN = $configObject.parentDN
$header = $configObject.header -split $delimiter
[string]$defaultUserPassword = $configObject.defaultUserPassword



function buildUserObject() {
    param (
        [Parameter(Mandatory = $true)]
        [string]$mapID,
        [Parameter(Mandatory = $true)]
        [string]$givenName,
        [Parameter(Mandatory = $true)]
        [string]$location,
        [Parameter(Mandatory = $true)]
        [string]$surName,
        [Parameter(Mandatory = $true)]
        [string]$telephoneNumber,
        [Parameter(Mandatory = $true)]
        [string]$email
    )

    if ([string]::IsNullOrEmpty($email)) {
        $email = $csvUserLine.UserPrincipalName.Split('@')[0] + "@polizei.berlin.de"
    }

    $newUser = @{
        #mandatory
        # "Path" entspricht dem Distinguished Name, aber ohne den 'CN=24318496,'-Teil, aka "X.500 OU path"
        # OU=LKA 725,OU=LKA 72,OU=LKA 7,OU=LKA,OU=Dienststellen,OU=Benutzer,OU=ad,DC=msd,DC=polizei,DC=berlin,DC=de
        Path                  = $location
        SamAccountName        = "msd$($mapID)"
        UserPrincipalName     = "msd$($mapID)@msd.polizei.berlin.de"
        Enabled               = $true
        ChangePasswordAtLogon = $true
        AccountPassword       = $(ConvertTo-SecureString $defaultUserPassword -AsPlainText -Force)
        Name                  = $mapID
        DisplayName           = "$($givenName) $($surName)"
        GivenName             = $givenName
        Surname               = $surName
        EmailAddress          = $email
        OfficePhone           = $csvUserLine.telephoneNumber #OBS! Get-ADUser uses telephoneNumber, Set-ADUser only knows OfficeTelephone or MobilePhone
    }

    return $newUser
}

#Remove the header
$data = Import-Csv -Path $csvPath -Delimiter $delimiter -Header $header -Encoding UTF8

#Add the default password to every user
foreach ($user in $data) {
    $user | Add-Member -MemberType NoteProperty -Name 'password' -Value $defaultUserPassword
    Write-Host "User $($user.DisplayName) has been added with password $($user.password)"
}

$someUser = Get-ADUser -Filter * -SearchBase $parentDN
Write-Host $someUser