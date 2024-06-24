<#
    .Synopsis
    Konfigurationsdatei für AD-Import
#>
@{
    # das Zeichen, welches in der CSV zum Trennen der Zeileneinträge verwendet wird (Excel-Standard =';')
    [string]$trennzeichen = ';'
    # gibt an wie viele Zeilen der CSV bearbeitet werden sollen (0 oder $null für alle)
    [int]$maxLines = 10

    # MAP-AD OU-Präfix im User-CanonicalName, welches nicht reproduziert werden soll
    [string]$mapADOUPraefix = "int.polizei.berlin.de/Polizei/"
    # Höchster OU-Knoten, ab welchen Nutzer und OUs im MSD-Netz "eingesetzt" werden sollen
    $parentDN = 'OU=Dienststellen,OU=Benutzer,OU=ad,DC=msd,DC=polizei,DC=berlin,DC=de'
    # Standard-/Initalkennwort für neue Nutzer
    [string]$defaultUserPassword = '***************************'
}
