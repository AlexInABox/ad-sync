Param(
    [Parameter(Mandatory = $true)]
    [string]$message
)

$logFile = "./modules/debug.log"

Write-Host $message
Add-Content -Path $logFile -Value $message