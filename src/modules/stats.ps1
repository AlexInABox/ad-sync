Param(
    [Parameter(Mandatory = $false)]
    [bool]$created = 0,
    [Parameter(Mandatory = $false)]
    [bool]$moved = 0,
    [Parameter(Mandatory = $false)]
    [bool]$updated = 0,
    [Parameter(Mandatory = $false)]
    [bool]$debugStats = 0
)
$statsFile = Join-Path -Path $PSScriptRoot -ChildPath "..\logs\stats.log"
#Modules
$debugModule = Join-Path -Path $PSScriptRoot -ChildPath "debug.ps1"

# Initialize default stats if file does not exist
if (-Not (Test-Path $statsFile)) {
    $stats = @{
        Created = 0
        Moved = 0
        Updated = 0
    }
} else {
    # Read the existing stats from the file
    $stats = Get-Content $statsFile | ConvertFrom-Json
}

# Increment the corresponding value based on the parameter
if ($created) {
    $stats.Created++
} elseif ($moved) {
    $stats.Moved++
} elseif ($updated) {
    $stats.Updated++
} elseif ($debugStats) {
    . $debugModule -message "Newly created: $($stats.Created)"
    . $debugModule -message "Moved: $($stats.Moved)"
    . $debugModule -message "Updated: $($stats.Updated)"
}

# Write the updated stats back to the file
$stats | ConvertTo-Json | Set-Content $statsFile