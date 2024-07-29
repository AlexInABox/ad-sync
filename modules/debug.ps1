Param(
    [Parameter(Mandatory = $true)]
    [string]$message,

    [Parameter(Mandatory = $false)]
    [bool]$debugEnabled = 1
)

$logFile = "./modules/debug.log"

if ($debugEnabled) {
    Write-Host $message
    Add-Content -Path $logFile -Value $message
}