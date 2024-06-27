Param(
    [Parameter(Mandatory = $true)]
    [string]$tablePath,

    [Parameter(Mandatory = $true)]
    [string]$configPath,

    [Parameter(Mandatory = $false)]
    [bool]$debugEnabled = 1
)

#Modules
$debugModule = Join-Path -Path $PSScriptRoot -ChildPath "\modules\debug.ps1"
$checkInputsModule = Join-Path -Path $PSScriptRoot -ChildPath "\modules\checkInputs.ps1"
$sanitizeModule = Join-Path -Path $PSScriptRoot -ChildPath "\modules\sanitize.ps1"
$syncModule = Join-Path -Path $PSScriptRoot -ChildPath "\modules\sync.ps1"



#Check if all required inputs are available
if (-Not (. $checkInputsModule -tablePath $tablePath -configPath $configPath -debugEnabled $debugEnabled)) {
    . $debugModule -message "At least one file you provided failed the checks!" -debugEnabled $debugEnabled
    return
}

. $debugModule -message  "All checks succeeded." -debugEnabled $debugEnabled

#Sanitize input table
$sanitizedTablePath = . $sanitizeModule -path $tablePath -debugEnabled $debugEnabled
if ($sanitizedTablePath -eq "") {
    . $debugModule -message "Failed to sanitize input table." -debugEnabled $debugEnabled
    return
}
. $debugModule -message  "Input table successfully sanitized!" -debugEnabled $debugEnabled

#Use the sanitized table to fill the Active Directory specified in the config
. $syncModule -path $sanitizedTablePath -configPath $configPath -debugEnabled $debugEnabled
. $debugModule -message  "Input table successfully sanitized!" -debugEnabled $debugEnabled

