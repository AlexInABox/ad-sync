  <#
    .SYNOPSIS
    Skript zum Importieren von AD-Nutzern anhand definierter CSV-Datei

    .EXAMPLE
    Import-ADUsers -csvPath '\\path\to\file.csv' -startLine 50 

    .NOTES
        Stand: 03.06.2024
    
    .PARAMETER csvPath
    Pfad zur Import-CSV
    .PARAMETER delimiter
    CSV-Trennzeichen
    .PARAMETER startLine
     Anzahl Zeilen der CSV-Datei die verarbeitet werden sollen (0=alle)
     .PARAMETER noDebug
     Explizite Angabe, dass Daten in das AD geschrieben werden sollen
#>
param(
    [cmdletbinding()]
    [string]$csvPath,       # Pfad zur Import-CSV
    [string]$delimiter=';',  # CSV-Trennzeichen
    [ValidateRange(0, [int]::MaxValue)]
    [int]$startLine=0,         # erste ausgewerte CSV-Zeile
    [ValidateRange(0, 10000)]
    [int]$lineStep=15,       # pausiert alle n Zeilen der CSV-Import-Datei 
    [string]$defaultPassword = 'Pilot23"§',
    # oberster OU-Knoten, ab welchem die neuen Nutzer eingepflegt werden
    $topLevel = @{
        DN = 'OU=Dienststellen,OU=Benutzer,OU=ad,DC=msd,DC=polizei,DC=berlin,DC=de';
        CN = 'msd.polizei.berlin.de/ad/Benutzer/Dienststellen/';
        mapCN = 'int.polizei.berlin.de/Polizei/'
    },
    # statischer Import-Pfad (für wiederholtes Arbeiten an derselben Datei)
    [string]$staticImport = '\\msd\dfs\Admin\AcitveDirectory\MA-Listen\240514_MAP-AD-Users\Dir4K_MOD.csv',
    # Sicherheitsschalter um unbeabsichtigte AD-Änderungen zu verhindern
    [switch]$noDebug,
    # Hashtable Abbildung von MAP-OUs auf MSD-OUs  @{'LKA 7 FueD AE EG ZAK BKS'='LKA 7 ZAK BKS'; ...}
    $ouMapping,
    # Hashtable Abbildung von MAP-Gruppen auf MSD-Gruppen
    $grpMapping,
    [string]$logError = 'error.log', #Basisname. wird um kompletten Dateipfad ergänzt
    [string]$logFile = 'import.log' #Basisname. wird um kompletten Dateipfad ergänzt
)


Import-Module ActiveDirectory

# TODO: if($retStat) $true iff SUCCESS
enum ReturnStatus {
    SUCCESS
    ERROR
    ABORT_USER 
}


function Write-Log {
    param (
        [string]$message,
        [string]$logFile=$logFile
    )
    Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $message"
}

function Export-SkippedUsers{
    [cmdletbinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$filePath,
        $Users
    )
    if(!$Users -or ($Users.Count -eq 0)){
        return
    }

    try{
        New-Item -Path $filePath -ItemType File -Force | Out-Null #ggf. Dateipfad anlegen
        [PSCustomObject] $Users.Values | Export-CSV -Path $filePath -Encoding UTF8 -Delimiter $delimiter -NoTypeInformation
    } catch {
        #emergency dump
        New-Item -Path "$PWD\skippedUsers.txt" -ItemType File -Force | Out-Null
        foreach($user in $Users){
            Add-Content -Path "$PWD\skippedUsers.txt" -Encoding utf8 -Value $user
        }
        Write-Error "$($_.Exception.Message)"
        Write-Error "Übersprungene Nutzer konnten nicht nach $filePath exportiert werden! Bitte Notfall-Export nach $PWD\skippedUsers.txt prüfen."
        $c = Read-Host "'AllUsers'-Variable (zusätzlich) auf die Console ausgeben? (J/N)"
        if($c.toUpper() -eq 'J'){
            Write-Host $Users
        }
    }

}

# TODO: Alternative?
# https://www.sapien.com/blog/2014/10/21/a-better-tostring-method-for-hash-tables/
function Convert-ObjToStr{
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]
        $hashtable
    )
    if(!$hashtable -or ($hashtable.Count -eq 0)){
        return "@{}"
    }
    $hashstr = "@{"
    $keys = $hashtable.keys
    foreach ($key in $keys)
    {
        $v = $hashtable[$key]
        if ($key -match "\s")
        {
            $hashstr += "`"$key`"" + "=" + "`"$v`"" + ";"
        }
        else
        {
            $hashstr += "$key" + "=" + "`"$v`"" + ";"
        }
    }
    $hashstr.TrimEnd(';') += "}"
    return $hashstr
}

<#
    .SYNOPSIS
    Nutzer zeilenweise aus CSV in Hashtable/Dict einlesen

    #TODO: refactor for liny-by-line-processing
#>
function Load-UsersFromFile {
   # [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", Scope="Function", Target="*")]
    [cmdletbinding()]
    param(
        # Dateipfad zur Datei mit den AD-Nutzern.
        [parameter(Mandatory)]
        [ValidateNotNullorEmpty()]
        [string]$filePath
    )

    return Import-csv -Encoding 'UTF8' -Delimiter $delimiter -Path $filePath
}

function Build-NewUser{
    [cmdletbinding()]
    param(
        $csvUserLine,
        $DistNamePath,
        $ouList
    )
    $email = $csvUserLine.Mail
    if([string]::IsNullOrEmpty($email)){
        $email = $csvUserLine.UserPrincipalName.Split('@')[0] + "@polizei.berlin.de"
    }
    # "msd.polizei.berlin.de/ad/Benutzer/Dienststellen/" + "LKA/LKA 3/.." + "/24318496"
    #"$($topLevel.CN)$([string]::Join('/',$ouList))/$($csvUserLine.Name)"
    #$canonicalName = $csvUserLine.CanonicalName.Replace($topLevel.mapCN,$topLevel.CN)

    #https://learn.microsoft.com/en-us/powershell/module/activedirectory/new-aduser?view=windowsserver2019-ps
    $newUser = @{
        #mandatory
        # "Path" entspricht dem Distinguished Name, aber ohne den 'CN=24318496,'-Teil, aka "X.500 OU path"
        # OU=LKA 725,OU=LKA 72,OU=LKA 7,OU=LKA,OU=Dienststellen,OU=Benutzer,OU=ad,DC=msd,DC=polizei,DC=berlin,DC=de
        Path = $DistNamePath
        SamAccountName = "msd$($csvUserLine.SamAccountName)"
        
        UserPrincipalName = "msd$($csvUserLine.SamAccountName)@msd.polizei.berlin.de"
        Enabled = $true
        ChangePasswordAtLogon = $true
        AccountPassword = $(ConvertTo-SecureString $defaultPassword -AsPlainText -Force)
        Name = $csvUserLine.Name #mapID/PersNr
        #CanonicalName = $canonicalName         #CN is created through New-ADUser and cannot be set
        DisplayName = "$($csvUserLine.GivenName) $($csvUserLine.Surname)"
        GivenName = $csvUserLine.GivenName
        Surname = $csvUserLine.Surname
        EmailAddress = $email
        OfficePhone = $csvUserLine.telephoneNumber #OBS! Get-ADUser uses telephoneNumber, Set-ADUser only knows OfficeTelephone or MobilePhone
    }
    return $newUser
}

function Check-UserInThisGroup{
    #[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", Scope="Function", Target="*")]
    [cmdletbinding()]
    param(
        [string]$userID,
        [string]$groupName
        )
        try{
            $grpMembers = Get-ADGroupMember -Identity $groupName | Select-Object -ExpandProperty Name
        } catch {
            return $false
        }
    return $grpMembers -contains $userID

}

function upsert-User{
    #[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", Scope="Function", Target="*")]
    [cmdletbinding()]
    param(
        $newUser,
        [string]$groupName,
        [string]$newUserCanonicalName,
        $mockAD
        )

    $oldUser = $null
    try{
        $oldUser = Get-ADUser -Identity "msd$($newUser.Name)" -Properties * # nicht mit DN suchen, falls OU-abhängig..?
    } catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        $oldUser = $false   #not necessary, just hiding the exception in the console
    }

    $retStats = @() #'return statusses' collects errors
    if ($oldUser){
        Write-Log -message "Import-Nutzer $($newUser.Name) ($($newUser.DisplayName)) existiert bereits im MSD-AD."

        # check differences
        $movedOU = ($oldUser.CanonicalName -ne $newUserCanonicalName)
        $userAlreadyInGrp = (Check-UserInThisGroup -userID $oldUser.Name -groupName $groupName)
        $diffKeys = @{}
        $excludeAttr = @("AccountPassword","Path","ChangePasswordAtLogon")
        foreach ($key in $newUser.keys){
            if($excludeAttr -contains $key){continue} # skip these attributes (don't compare/overwrite)
            if($newUser[$key] -ne $oldUser[$key]){
                $diffKeys[$key] = New-Object PSCustomObject -Property @{'new' = $newUser[$key];'old' = $oldUser[$key]}
            }
        }

        #keine Veränderungen nötig
        if(($diffKeys.Count -eq 0) -and !$movedOU -and $userAlreadyInGrp){
            Write-Log -message "Import-Nutzer $($oldUser.Name) hat keine neuen Werte/Eigenschaften und wird nicht aktualisiert."
            return [ReturnStatus]::SUCCESS
        }

        #veränderte Werte im MAP-Import > gefundene Unterschiede beschreiben
        $msg = "Für Nutzer $($oldUser.Name) ($($oldUser.DisplayName)) liegen im Import aktualisierte Werte vor:"
        $mapID = "/$($oldUser.Name)$" #trimEnd() wonky, use replace instead
        if($movedOU){$msg += "`n`tOU verändert:  `n`t`talt: $($oldUser.CanonicalName -replace $mapID, '') -> `n`t`tneu: $($newUserCanonicalName -replace $mapID, '')"}
        if(!$userAlreadyInGrp){$msg += "`n`tMitglied in neuer AD-Gruppe: $groupName"}
        $key = ''
        foreach ($key in $diffKeys.Keys){
            $msg += "`n`tVerändertes Nutzerattribut [$key]:  alt: $($diffKeys[$key].old) -> neu: $($diffKeys[$key].new)"
        }
        

        Write-Log -message $msg

        if($noDebug){
            #Bestätigung für Veränderung
            Write-Host $msg
            $choice = Read-Host "`nNutzereigenschaften aktualisieren (A) oder alte Werte belassen (B)?  (A/B)"
            if($choice.ToUpper() -ne 'A'){
                Write-Host "Nutzerwerte für $($oldUser.Name) werden NICHT aktualisiert."
                Write-Log -message "Nutzerwerte für $($oldUser.Name) werden NICHT aktualisiert."
                return [ReturnStatus]::ABORT_USER
            }
        }

        #TODO: refactor.  prepare actual Commands as string for conditional '-WhatIf' modification
        $ou_cmd = "Move-ADObject -Identity '$($oldUser.DistinguishedName)' -TargetPath '$($newUser.Path)' "
        $grp_cmd = "Add-ADGroupMember -Identity '$groupName' -Members '$($oldUser.DistinguishedName)' "
        $attr_cmd = "Set-ADUser -Identity '$($oldUser.DistinguishedName)' "

        #append -WhatIf for debug
        if (!$noDebug){$ou_cmd += '-WhatIf';$grp_cmd += '-WhatIf';$attr_cmd += '-WhatIf '}

        Write-Host "Aktualisiere Nutzerwerte..."
        Write-Log -message "Aktualisiere Nutzerwerte..."
        if(!$userAlreadyInGrp){
            try {
                Write-Log -message "Füge $($oldUser.Name) zur Gruppe $groupName hinzu."
                Invoke-Expression $grp_cmd
            } catch {
                Write-Log -logFile $logError -message "Fehler beim Hinzufügen des Nutzers $($oldUser.Name) zur Gruppe $groupName :`n$($_.Exception.Message)"
                $retStats +=  [ReturnStatus]::ERROR
            }
        }
        try {
            foreach ($key in $diffKeys.Keys){
                $attr_cmd_tmp = $attr_cmd
                Write-Log -message "Ändere $($oldUser.Name).$key von '$($diffKeys[$key].old)' auf '$($diffKeys[$key].new)'."
                #e.g.: "Set-ADUser -Identity .... (-WhatIf) -officePhone"
                $attr_cmd_tmp += "-$key '$($diffKeys[$key].new)'"
                Invoke-Expression $attr_cmd_tmp
            }
        } catch {
            Write-Log -logFile $logError -message "Fehler beim Ändern von Nutzerattributen: $($oldUser.Name).$key von '$($diffKeys[$key].old)' auf '$($diffKeys[$key].new)' :`n$($_.Exception.Message)"
            $retStats +=  [ReturnStatus]::ERROR
        }
        if($movedOU){   #user move last, b/c DN is changed
            try {
                Write-Log -logFile $logFile -message "Verschiebe $($oldUser.Name) von `n$($oldUser.DistinguishedName.Substring(12)) `nnach `n$($newUser.Path)."
                Invoke-Expression $ou_cmd #$oldUser.DistinguishedName changed!
            } catch {
                Write-Log -logFile $logError -message "Fehler beim Verschieben des Nutzers $($oldUser.Name) von `n$($oldUser.DistinguishedName) `nnach `n$($newUser.Path).:`n$($_.Exception.Message)"
                $retStats += [ReturnStatus]::ERROR
            }
        }
        
        $retStats +=  [ReturnStatus]::SUCCESS
        return $retStats  

    } #endif oldUser

    #neuen Nutzer anlegen und zu Gruppe hinzufügen (Annahme: OU und Grp schon erstellt)
    Write-Log "Import-Nutzer $($newUser.Name) ($($newUser.DisplayName)) wird neu angelegt."
    if(!$noDebug){
        <# #####wirft ggf. Fehler, weil neue OU / Grp nicht tatsächlich im AD angelegt wurden, TODO Mock-AD-Funktionen erstellen###
        try{ New-ADUser @newUser -WhatIf } 
        catch {
            Write-Log -logFile $logError -message "Fehler beim Anlegen von neuem Nutzer $($newUser.Name):`n$($_.Exception.Message)"
            return @([ReturnStatus]::ERROR)
        }
        try { Add-ADGroupMember -Identity "$groupName" -Members "CN=$($newUser.Name),$($newUser.Path)" -WhatIf }
        catch {
            Write-Log -logFile $logError -message "Fehler beim Hinzufügen des neuen Nutzers $($newUser.Name) zur Gruppe $groupName :`n$($_.Exception.Message)"
            return @([ReturnStatus]::ERROR)
        }#>
        return @([ReturnStatus]::SUCCESS)
    } 

    #persist!
    try {   New-ADUser @newUser }
    catch {
        Write-Error "Fehler beim Anlegen des Nutzers $($newUser.Name). Fehler wurde nach $(Convert-Path $logError) geloggt. Fehlertext:`n$($_.Exception.Message)"
        Write-Log -logFile $logError -message "Konnte neuen Nutzer $($newUser.Name) nicht anlegen. Nutzerobjekt:`n$(Convert-ObjToStr $newUser)"
        return @([ReturnStatus]::ERROR)
    }
    try { Add-ADGroupMember -Identity "$groupName" -Members "CN=$($newUser.Name),$($newUser.Path)" }
    catch {
        Write-Log -logFile $logError -message "Fehler beim Hinzufügen des neuen Nutzers $($newUser.Name) zur Gruppe $groupName :`n$($_.Exception.Message)"
        return @([ReturnStatus]::ERROR)
    }
    return @([ReturnStatus]::SUCCESS)
}

function upsert-Group{
    #[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", Scope="Function", Target="*")]
    [cmdletbinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$groupName,
        [ValidateNotNullOrEmpty()]
        [string]$ouPath,
        $grpMapping=@{},    #pass by reference
        $mockAD = @{}
        )

    #ggf. MAP-Gruppename mit zuvor definiertem MSD-Gruppen-Alias ersetzen
    if($grpMapping -and $grpMapping[$groupName]){
        $groupName = $grpMapping[$groupName]
    }

    $newGroup = "CN=$groupName,$ouPath"
    if([adsi]::Exists("LDAP://$newGroup")){
            return [ReturnStatus]::SUCCESS
    } 
    #im Debug-Zweig, zusätzlich prüfen ob die OU bereits im mockAD angelegt wurde
    if (!$noDebug -and $mockAD[$groupName]) { 
            return [ReturnStatus]::SUCCESS
    }

    #Persist!
    $choice = Read-Host "Die AD-Gruppe $groupName existiert noch nicht, soll sie an der Stelle '$($ouPath.trimEnd($topLevel.DN)),...' (in der OU ganz links) neu angelegt werden? ( (J)a - (S)kip - (C)ustom )"
    if('J','C' -notcontains $choice.ToUpper()){ #alles außer J und C
        # User-Abbruch
        Write-Log -message "Nutzer-Abbruch: Gruppe '$groupName' in '$ouPath' NICHT angelegt."
        return [ReturnStatus]::ABORT_USER
    }
    
    # abweichenden Gruppennamen vergeben
    if ($choice.ToUpper() -eq 'C') {
        $newGrpName = ''
        $conf = ''
        while ($conf.ToUpper() -ne 'J') {
            $newGrpName = Read-Host "Neuen Gruppennamen eingeben"
            $conf = Read-Host "$newGrpName verwenden? (J/N)"
        }
        Write-Log -message "MAP-Gruppename '$groupName' durch '$newGrpName' ersetzt."
        # für restliche Nutzer automatisch anpassen?
        $resp = Read-Host "Gruppen-Mapping ['$groupName'(MAP) <> '$newGrpName'(MSD)] für restliche Nutzer anwenden? (J/N)"
        if ($resp.ToUpper() -eq 'J'){
            $grpMapping[$groupName] = $newGrpName #modify referenced object
            Write-Log "Gruppen-Mapping ['$groupName'(MAP) <> '$newGrpName'(MSD)] eingetragen."}
        
        $groupName = $newGrpName

        #neu gewählten Namen ebenfalls prüfen, ob bereits angelegt
        $newGroup = "CN=$groupName,$ouPath"
        if([adsi]::Exists("LDAP://$newGroup")){ return [ReturnStatus]::SUCCESS  } 
        if (!$noDebug -and $mockAD[$groupName]) { return [ReturnStatus]::SUCCESS }
    } 

    $newGrpCmd = "New-ADGroup -Name '$groupName' -SamAccountName '$groupName' -GroupCategory Security -GroupScope Global -Path '$ouPath' "
    if (!$noDebug){
        $newGrpCmd += "-WhatIf"
    }        
        
    try {
        if (!$noDebug){
            #start a new thread to capture WhatIf-Output (Workaround to https://github.com/PowerShell/PowerShell/issues/9870)
            $msg = & pwsh -c "New-ADGroup -Name `'$groupName`' -SamAccountName `'$groupName`' -GroupCategory Security -GroupScope Global -Path `'$ouPath`' -WhatIf "
            Write-Log -message $msg
            $mockAD[$groupName] = $true
        }  else {
            New-ADGroup -Name "$groupName" -SamAccountName "$groupName" -GroupCategory Security -GroupScope Global -Path "$ouPath"
            #Invoke-Expression $newGrpCmd
        }
    } catch {
        Write-Log -logFile $logError -message "Fehler beim Anlegen der AD-Gruppe $groupName in '$ouPath' :`n$($_.Exception.Message)"
        return [ReturnStatus]::ERROR
    }
    Write-Log -message "Neue AD-Gruppe '$groupName' erfolgreich angelegt."
    return [ReturnStatus]::SUCCESS
    
}

function upsert-OU{
    #[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", Scope="Function", Target="*")]
    [cmdletbinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$ouName,
        [ValidateNotNullOrEmpty()]
        [string]$ouPath,
        $ouList,
        $ouMapping = @{},    #pass by reference
        $mockAD = @{}
        )
    #check to see if we're lucky (kompletter OU-Pfad existiert)
    if([adsi]::Exists("LDAP://$ouPath")){
        return [ReturnStatus]::SUCCESS
    }
    #im Debug-Zweig: zusätzlich noch im mockAD gucken, ob nachträglich angelegt
    if (!$noDebug -and $mockAD[$ouName]){    
        return [ReturnStatus]::SUCCESS
    }

    #beginnend bei der obersten OU (z.B: LKA oder LPD) schrittweise abwärts die weiteren OU-Ebenen prüfen oder anlegen
    $tmpOU_Base = $topLevel.DN
    $i = -1
    foreach($ou in $ouList){
        ++$i
        if($ouMapping[$ou]){
            $ou = $ouMapping[$ou]
        }
        $tmpOU_New = "OU=$ou,$tmpOU_Base"
        if([adsi]::Exists("LDAP://$tmpOU_New")){    #prüfen ob diese OU-Ebene existiert
            $tmpOU_Base = $tmpOU_New
            continue
        }
        if (!$noDebug -and $mockAD[$ou]){    #debug: prüfen ob diese OU-Ebene pseudo-existiert
            $tmpOU_Base = $tmpOU_New
            continue
        }
        
        #Persist!
        Write-Host "Folgende OU aus dem MAP-Import ist im MSD-AD nicht vorhanden und müsste neu angelegt werden: '$ou'"
        $parentOU = if($i -le 0) { "Benutzer-Root '$($topLevel.DN.Substring(0,$topLevel.DN.IndexOf(',')))'" } else { $ouList[$i-1] }
        $choice = Read-Host "Soll die OU '$ou' neu im AD an der Stelle '$($tmpOU_Base.trimEnd($topLevel.DN)),...' (vorne / unter '$parentOU')) angelegt werden? ( (J)a - (S)kip - (C)ustom )"
        if('J','C' -notcontains $choice){
            # User-Abbruch
            Write-Log -logFile $logError -message "Nutzer-Abbruch: OU '$ou' in '$tmpOU_Base' NICHT angelegt."
            return [ReturnStatus]::ABORT_USER #return, nicht continue, da tiefere OU-Ebenen auf diese aufbauen würden
        }

        #neue OU anders benennen als aus CSV übergeben
        if($choice.ToUpper() -eq 'C'){
            $ouNewName = ''
            $conf = ''
            while (!$conf) {
                $ouNewName = Read-Host "Neuen OU-Namen eingeben: "
                $conf = Read-Host "$ouNewName verwenden? (J/N)"
                if ($conf.ToUpper() -eq 'J'){$conf=$true}
            }
            Write-Log -message "MAP-OU '$ou' durch '$ouNewName' ersetzt."
            $resp = Read-Host "OU-Mapping ['$ou'<>'$ouNewName'] für restliche Nutzer anwenden? (J/N)"
            if ($resp.ToUpper() -eq 'J'){
                $ouMapping[$ou]=$ouNewName #modify referenced object
                Write-Log "OU-Mapping ['$ou'(MAP) <>'$ouNewName'(MSD)] eingetragen."}
            $ou = $ouNewName
        }  
        
        try {
            if (!$noDebug){
                Write-Log -message "Erstelle OU:   $tmpOU_New"
                #$msg = & pwsh -c {New-ADOrganizationalUnit -Name $ou -Path $tmpOU_Base -WhatIf}
                #Write-Log -message $msg
                New-ADOrganizationalUnit -Name $ou -Path $tmpOU_Base -WhatIf
                $mockAD[$ou] = $true
                $tmpOU_Base = $tmpOU_New
                continue
            } 
            Write-Log -message "Erstelle OU:   $tmpOU_New"
            New-ADOrganizationalUnit -Name $ou -Path $tmpOU_Base
        } catch {
            Write-Log -logFile $logError -message "Fehler beim Anlegen der OU $ou in $tmpOU_Base :`n$($_.Exception.Message)"
            return [ReturnStatus]::ERROR
        }
        Write-Log -message "Neue OU '$tmpOU_New' erfolgreich angelegt."

        $tmpOU_Base = $tmpOU_New

    } #foreach OU in List

    return [ReturnStatus]::SUCCESS
}

<#
    .SYNOPSIS
    Prüft ob das übergebene Nutzer-Objekt leere/ungültige Attribute enthält
    Passwort-Feld wird übersprungen, Telefonfeld ignoriert
#>
function  Check-User{
    [cmdletbinding()]
    param($user)
    $res = [ReturnStatus]::SUCCESS
    foreach($key in $user.keys){
        if($key -eq "AccountPassword"){continue} # 
        if ([string]::IsNullOrEmpty($user[$key])) {
            if($key -eq "OfficePhone"){
                Write-Log -message "Für Nutzer $($user.Name) ($($user.DisplayName)) wurde keine Telefonnummer im Import gefunden. Feld bleibt leer."
                continue
            }
            return [ReturnStatus]::ERROR
        }
    }
    return $res
}

<#
source CanonicalName: int.polizei.berlin.de/Polizei/LKA/LKA 2/LKA 21/LKA 211/24023074
source fields: SamAccountName, Name, CanonicalName, DisplayName, GivenName, Surname, Mail

target DistinguishedName = CN=24318496,OU=LKA 725,OU=LKA 72,OU=LKA 7,OU=LKA,OU=Dienststellen,OU=Benutzer,OU=ad,DC=msd,DC=polizei,DC=berlin,DC=de

AD User Object Properties:

*all* possible attributes: see https://www.easy365manager.com/how-to-get-all-active-directory-user-object-attributes/
see all set parameters (specific user): Get-ADUser -Identity mdsd24318496 -Properties *

#>
function  Convert-Users{
    [cmdletbinding()]
    param(
        [ValidateNotNull()]
        $Users,
        [ValidateRange(0, 10000)] #[int]::MaxValue
        [int]$startLine=0,
        [ValidateRange(1, 10000)]
        [int]$lineStep=15,
        $ouMappingArg = @{},
        $grpMappingArg = @{},
        $exportPathSkippedUsers
    )
    if($startLine -gt 0){ #Objekt-Indizes starten bei 0.. TODO: do the math
        --$startLine
    }
    # Import-CSV gibt eigentlich einen Object-Array zurück, bei nur einer Zeile aber direkt den Zeileninhalt als PSCustomObject
    # damit die Zugriffe auf "Users[n]" konsistent funktionieren, packen wir das einzelne Objekt manuell in einen Array...
    if($Users.Count -eq 1){
        [Object[]]$objArray = @()
        $objArray += $Users
        $Users=$objArray
    }

    if($startLine -gt $Users.Count){
        Write-Error "`nStartzeile höher gesetzt als gelesene Zeilen in Quelldatei vorhanden ( $($startLine+1) > $($Users.Count))"
        return
    }

    $skippedUsers = @{}
    $mockADForDebug = @{}
    $ouMapping = $ouMappingArg.PSObject.Copy()
    $grpMapping = $grpMappingArg.PSObject.Copy()
    #Für jede ausgelesene CSV Zeile...
    for($currLine=$startLine; $currLine -lt $Users.Count; $currLine++){

        # Prüfen ob Pause (angegebener Zeilen-Intervall erreicht)
        if(  (($currLine-$startLine) -ge $lineStep) -and (($currLine-$startLine) % $lineStep -eq 0)){
            $linesLeft = ($Users.Count - $startLine - $currLine)
            $choice = Read-Host "`nZeilenintervall ($lineStep) bei Z. $($currLine+1) erreicht: $($currLine-$startLine) Zeilen verarbeitet, $linesLeft verbleiben ($($Users.Count) gesamt, Start bei $($startLine+1)), möchten Sie fortfahren? ('N' für Ende, sonst beliebig)"
            if($choice.ToUpper().Equals('N')){
                Write-Log -message "Import bei Zeile $($currLine+1) nach $($currLine-$startLine) Zeilen durch Nutzer abgebrochen."
                Write-Host "`nImport bei Zeile $($currLine+1) von $($Users.Count) nach $($currLine-$startLine) verarbeiteten Zeilen durch Nutzer abgebrochen."
                break
            }
        }
        if( ($currLine -lt 0) -or ($currLine -ge ($Users.Count))){
            Write-Warning "Liste ggf. nicht vollständig bearbeitet (possible out-of-bounds at line $currLine)"
            Write-Log -message "Liste ggf. nicht vollständig bearbeitet (possible out-of-bounds at line $currLine)"
            Write-Log -logFile $logError -message "Liste ggf. nicht vollständig bearbeitet (possible out-of-bounds at line $currLine)"
            break
        }
        
        #Informationen aus CSV-USer-Zeile extrahieren
        $Kommissariat, $DistNamePath, $ouList = ConvertFrom-CanonicalOU -CanonicalName $Users.Get($currLine).CanonicalName

        #Informationen für neuen Nutzer sammeln
        $newUser = Build-NewUser -csvUserLine $Users[$currLine] -DistNamePath $DistNamePath -ouList $ouList
        $newUserCanonicalName = $Users.Get($currLine).CanonicalName
        $newUserCanonicalName = $newUserCanonicalName.Replace($topLevel.mapCN,$topLevel.CN)
        $kommGruppe = "g-org-" + $Kommissariat
        
        #Vorrausetzungen für Anlage prüfen/herstellen
        $resUser = Check-User $newUser
        $resOU = upsert-OU -ouName $ouList[-1] -ouPath $DistNamePath -ouList $ouList -ouMapping $ouMapping -mockAD $mockADForDebug
        #TODO: check if OU was customized. if so, update params...
        $resGrp = upsert-Group -groupName $kommGruppe -ouPath $DistNamePath -grpMapping $grpMapping -mockAD $mockADForDebug

        $errMesgs = ""
        if ($resUser -ne [ReturnStatus]::SUCCESS){
            $errMesgs += "`n`t- Erzeugter Nutzer hat fehlende Attribute."
        }
        if ($resOU -ne [ReturnStatus]::SUCCESS){
            $errMesgs += "`n`t- Ziel-OU '$($ouList[-1])' für Nutzer konnte nicht erstellt werden."
        }
        if ($resGrp -ne [ReturnStatus]::SUCCESS){
            $errMesgs += "`n`t- Ziel-Gruppe für Nutzer konnte nicht erstellt werden."
        }
        if ($errMesgs){
            Write-Warning $errMesgs
            Write-Host "CSV-Zeile $($currLine+1): Nutzer $($newUser.Name) ($($newUser.DisplayName)) aus Zeile $currLine wird nach $(Convert-Path $logError) geloggt und übersprungen."
            Write-Log -logFile $logError -message "CSV-Zeile $($currLine+1): Nutzer $($newUser.Name) ($($newUser.DisplayName)) wird übersprungen, aufgrund: $errMesgs `n`t Objektdaten: `n$(Convert-ObjToStr $newUser)"
            $Users[$currLine] | Add-Member -Name 'line' -Value $currLine -Type NoteProperty
            $skippedUsers[$currLine] = $Users[$currLine]
            #$currLine=$currLine+1
            continue
        }

        # prerequisites good, create/update user

        #ggf. MAP-Gruppename/OU mit zuvor definiertem MSD-Gruppen/OU-Alias ersetzen
        if($grpMapping -and $grpMapping[$kommGruppe]){
            $kommGruppe = $grpMapping[$kommGruppe]
        }
        foreach ($oldOU in $ouMapping.Keys){
            $newUser.Path = $newUser.Path.Replace($oldOU,$ouMapping[$oldOU])
            $newUserCanonicalName = $newUserCanonicalName.Replace($oldOU,$ouMapping[$oldOU])
        }
        $retStats = upsert-User -newUser $newUser -groupName $kommGruppe -newUserCanonicalName $newUserCanonicalName -mockAD $mockADForDebug

        # create/update user successful?
        if([ReturnStatus]::ERROR, [ReturnStatus]::ABORT_USER | Where-Object {$retStats -contains $_}){
            Write-Host "CSV-Zeile $($currLine+1): Fehler/Nutzer-Abbruch beim Verarbeiten des Nutzers $($newUser.Name) ($($newUser.DisplayName)). Wird nach $(Convert-Path $logError) geloggt und übersprungen."
            Write-Log -logFile $logError -message "CSV-Zeile $($currLine+1): Fehler/Nutzer-Abbruch beim Verarbeiten des Nutzers $($newUser.Name) ($($newUser.DisplayName)). Objektdaten: `n$(Convert-ObjToStr $newUser)"
            $Users[$currLine] | Add-Member -Name 'line' -Value $currLine -Type NoteProperty
            $skippedUsers[$currLine] = $Users[$currLine]
            #$currLine=$currLine+1
            continue
        }
        
        # increment line/user count
        #$currLine=$currLine+1

    } #end foreach

    Write-Log "Skipped Users:`n$(Convert-ObjToStr $skippedUsers)"
    Export-SkippedUsers -filePath $exportPathSkippedUsers -Users $skippedUsers

    Write-Log "Gemappte OUs:`n$(Convert-ObjToStr $ouMapping)"
    Write-Log "Gemappte Gruppen:`n$(Convert-ObjToStr $grpMapping)"

}


        <#
        $sAM = $newUser.SamAccountName
        $exists = Get-ADUser -Filter "SamAccountName -like `$sAM" #-SearchBase "OU=Dienststellen,OU=Benutzer,OU=ad,DC=msd,DC=polizei,DC=berlin,DC=de"
        #echo $exists | Write-Host
        if ($exists){
            echo $("User {0} existiert bereits und wird nicht neu angelegt." -f $newUser.SamAccountName)
        } else {
            echo $("User {0} wird angelegt" -f $newUser.SamAccountName)
            New-ADUser @newUser
            Add-ADGroupMember -Identity $kommGruppe -Members $newUser.SamAccountName
        } 
        #>

# convert CanonicalName (MAP)
#   "int.polizei.berlin.de/Polizei/LKA/LKA 2/LKA 21/LKA 211/24023074"
# to
#   Kommissariat + DistinguishedName (MSD)
#   "lka211", "OU=LKA 211,OU=LKA 21,OU=LKA 2,OU=LKA,OU=Dienststellen,OU=Benutzer,OU=ad,DC=msd,DC=polizei,DC=berlin,DC=de"
#
function ConvertFrom-CanonicalOU {
    [cmdletbinding()]
    param(
        [parameter(Mandatory, ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True)]
        [ValidateNotNullorEmpty()]
        [string]$CanonicalName
    )
    process {
        #int.polizei.berlin.de/Polizei/LKA/LKA 2/LKA 21/LKA 211/24023074
        # to
        # ['LKA', 'LKA 2','LKA 21','LKA 211']       TODO: Umgang mit "LKA 1 AE / OFA"...
        $chunks = $CanonicalName.Split('/')
        $chunks = $chunks[2..($chunks.Length-2)]  #TODO: check input!
        $ouList = $chunks.PSObject.Copy()

        [array]::Reverse($chunks)
        #$chunks = $chunks[1..$chunks.Length-2]

        $Kommissariat = $chunks[0]
        $Kommissariat = $Kommissariat.ToLower().Replace(' ','') #TODO: other chars?

        # ['LKA', 'LKA 211','LKA 21','LKA 2']
        # to
        # "LKA,OU=LKA 211,OU=LKA 21,OU=LKA 2,OU=LKA"
        $Dienststelle = [string]::Join(',OU=',$chunks)

        # DistName = 'OU=' + 'LKA 211,OU=LKA 21,OU=LKA 2' + ',OU=' + 'OU=Dienststellen,OU=Benutzer,OU=ad,...'
        $DistName = "OU=${Dienststelle},$($topLevel.DN)"
        return $Kommissariat, $DistName, $ouList
    }
}

function Print-Help{
    #[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", Scope="Function", Target="*")]
    param ()
    #Get-Help $MyInvocation.MyCommand.Definition
    #$MyInvocation.MyCommand.Name
    "
            Verwendung:
            $((Get-ChildItem $PSCommandPath).Name) -csvPath '\\pfad\zur\import.csv' 
                    -noDebug           AD tatsächlich manipulieren (kein Testlauf!)
                (opt.)
                    -delimiter ';'     CSV-Spalten-Trennzeichen
                    -startLine 50      erste ausgewerte CSV-Zeile
                    -lineStep 15       pausiert alle n Zeilen
        "
}

function Print-Params{
    #[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", Scope="Function", Target="*")]
    param()
    foreach ($key in $MyInvocation.MyCommand.Parameters){
        $val = (Get-Variable -Name $key -ValueOnly)
        Write-Host "$key = $val"
    }

}


##
# "main"
##

# print help when no arguments given
if(($PSBoundParameters.Count -eq 0)){
    #Get-Help $MyInvocation.MyCommand.Definition
    Print-Help
    return
}

# CSV-Datei oder Pfad aus diesem Skript verwenden?
$csvGivenAndGood = ((Test-Path -Path $csvPath) -and ((Get-ChildItem -Path $csvPath).Length -ne "0"))
$fallbackGivenAndGood = ((Test-Path -Path $staticImport) -and ((Get-ChildItem -Path $staticImport).Length -ne "0"))

# both bad
if (!$csvGivenAndGood -and !$fallbackGivenAndGood){
    Write-Error "`nKeine CSV-Datei gefunden oder leer."
    return
}

#bad csv, offer fallback
if (!$csvGivenAndGood -and $fallbackGivenAndGood){
    Write-Host "`nGespeicherte CSV-Datei gefunden:   $staticImport"
    $choice = Read-Host "Mit   $( (Get-ChildItem $staticImport).Name)   fortfahren? (J/N)"
    if(-Not $choice.ToUpper().Equals('J')){
        return
    }
    $csvPath = $staticImport
}

# simulieren oder Echtlauf?
$prefix = ''
if(!$noDebug){
    Write-Host "`n`t-noDebug Parameter nicht bestätigt, Änderungen werden NICHT ins AD gespeichert!"
    $prefix = 'debug-'
}

#Name der Importdatei vereinfachen für logfile-Namen
$importFilename = (Get-ChildItem $csvPath).Name
$importFilename = $importFilename -replace "[ \.-]" # '_' is trouble..

#create logfiles
$logError = Join-Path $PWD 'logs' "$(Get-Date -Format 'yyMMdd-HHmmss-')$importFilename-$prefix$logError"
$logFile = Join-Path $PWD 'logs' "$(Get-Date -Format 'yyMMdd-HHmmss-')$importFilename-$prefix$logFile"
New-Item -Path $logError -ItemType File -Force | Out-Null #TODO: schluckt auch Exceptions..
New-Item -Path $logFile -ItemType File -Force | Out-Null

#good csv, use $csvPath
Write-Host "`nVerarbeite: $((Get-ChildItem $csvPath).Name)"
Write-Log -message "Verarbeite: $((Get-ChildItem $csvPath).Name)"

$Users = Load-UsersFromFile -filePath $csvPath
if(!$Users){
    Write-Error "`nFehler beim Einlesen der Nutzer-CSV-Datei."
    return 1
} else {
    Write-Host "`nNutzer aus $csvPath erfolgreich eingelesen."
    Write-Log -message "Nutzer aus $csvPath erfolgreich eingelesen."
}

$ouMapping = @{}
$grpMapping = @{}
$exportPathSkippedUsers = Join-Path $PWD 'logs' "$(Get-Date -Format 'yyMMdd-HHmmss-')$importFilename-$($prefix)skippedUsers.csv"
Convert-Users -Users $Users -startLine $startLine -lineStep $lineStep -ouMapping $ouMapping -grpMapping $grpMapping -exportPathSkippedUsers $exportPathSkippedUsers

Write-Host "`nImport abgeschlossen. Ergebnis wurde in $(Convert-Path $logFile) protokolliert.`n"
if(Test-Path $exportPathSkippedUsers){
    Write-Host "Übersprungene Nutzer nach $(Convert-Path $exportPathSkippedUsers) exportiert.`n"
}

##
#
#   Nach Abschluss des Skripts müssen die erzeugten AD-Gruppen noch händisch in die Behördenhierarchie verschachtelt werden!
#
##




<#

# print help when no arguments given
if(($PSBoundParameters.Count -eq 1) -and ($PSBoundParameters | Where-Object { $_.keys -Match "(h|help|-h|--h|--help|-help|-\\?)"} ) ){
    #Get-Help $MyInvocation.MyCommand.Definition
    Print-Help
    return
}
if(($args.Count -eq 1) -and ($args | Where-Object { $_ -Match "(h|help|-h|--h|--help|-help|-\\?)"} ) ){
    #Get-Help $MyInvocation.MyCommand.Definition
    Print-Help
    return
}

#>
