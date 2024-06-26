Param(
    [Parameter(Mandatory = $true)]
    [string]$path,

    [Parameter(Mandatory = $false)]
    [bool]$debugEnabled = 1
)

$tmpDirectory = Resolve-Path ".\tmp"

function clearTMP {
    Remove-Item -Path $tmpDirectory"\*"
}
function copyTableToTMP {
    param (
        [string]$path
    )

    Copy-Item -path $path -Destination $tmpDirectory
}

#TODO: Sanitze based on rules or interaction with the user

clearTMP
copyTableToTMP -path $path