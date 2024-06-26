Param(
    [Parameter(Mandatory = $true)]
    [string]$message,

    [Parameter(Mandatory = $false)]
    [bool]$debugEnabled = 1
)

if ($debugEnabled) {
    Write-Host $message
}