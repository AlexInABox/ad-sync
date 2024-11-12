Param(
    [Parameter(Mandatory = $true)]
    [string]$tablePath,

    [Parameter(Mandatory = $true)]
    [string]$configPath,

    [Parameter(Mandatory = $false)]
    [bool]$readOnly = 1
)

#Modules
$debugModule = Join-Path -Path $PSScriptRoot -ChildPath "\modules\debug.ps1"
$statsModule = Join-Path -Path $PSScriptRoot -ChildPath "\modules\stats.ps1"
$checkInputsModule = Join-Path -Path $PSScriptRoot -ChildPath "\modules\checkInputs.ps1"
$sanitizeModule = Join-Path -Path $PSScriptRoot -ChildPath "\modules\sanitize.ps1"
$syncModule = Join-Path -Path $PSScriptRoot -ChildPath "\modules\sync.ps1"

function exitScript {
    . $debugModule -message "Exiting script."
    . $statsModule -debugStats 1
    $date = Get-Date -Format "yyddMM_HHmm"
    Copy-Item "./logs/debug.log" "./logs/debug_$date.log"
    Copy-Item "./logs/stats.log" "./logs/stats_$date.log"
    Exit
}

#Delete old logs
try {
    Remove-Item -Path "./logs/debug.log" -ErrorAction Stop
    New-Item -ItemType file -Path "./logs/debug.log"
}
catch {
    . $debugModule -message "No old logs found."
    New-Item -ItemType file -Path "./logs/debug.log"
}
#Delete old stats
try {
    Remove-Item -Path "./logs/stats.log" -ErrorAction Stop
}
catch {
    . $debugModule -message "No old stats found."
}

#Check if all required inputs are available
if (-Not (. $checkInputsModule -tablePath $tablePath -configPath $configPath)) {
    . $debugModule -message "At least one file you provided failed the checks!"
    exitScript
}
. $debugModule -message  "All checks succeeded."
. $debugModule -message  " "

#Sanitize input table
$sanitizedTablePath = . $sanitizeModule -path $tablePath -configPath $configPath
if ($sanitizedTablePath -eq "") {
    . $debugModule -message "Failed to sanitize input table."
    exitScript
}
. $debugModule -message  "Input table successfully sanitized!"
. $debugModule -message  " "

#Use the sanitized table to fill the Active Directory specified in the config
. $syncModule -csvPath $sanitizedTablePath -configPath $configPath -readOnly $readOnly
. $debugModule -message  "Script finished. Exiting. (Yippie :3)"
. $debugModule -message  " "

#Print the stats
. $statsModule -debugStats 1

$date = Get-Date -Format "yyddMM_HHmm"
Copy-Item "./logs/debug.log" "./logs/debug_$date.log"
Copy-Item "./logs/stats.log" "./logs/stats_$date.log"