param(
    $inputstring
)

Write-Host ($inputstring.ToLower() -replace " ", "")