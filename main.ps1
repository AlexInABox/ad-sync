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



if (-Not (. $checkInputsModule -tablePath $tablePath -configPath $configPath -debugEnabled $debugEnabled)) {
    . $debugModule -message "At least one file you provided failed the checks!" -debugEnabled $debugEnabled
    return
}

. $debugModule -message  "All checks succeeded." -debugEnabled $debugEnabled