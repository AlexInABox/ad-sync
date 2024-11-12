Param(
    [Parameter(Mandatory = $true)]
    [string]$message
)

$logFile = Join-Path -Path $PSScriptRoot -ChildPath "..\logs\debug.log"

Write-Host $message
Add-Content -Path $logFile -Value $message