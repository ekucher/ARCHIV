$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot

$files = Get-ChildItem -Path $root -Recurse -Filter *.ps1 -File |
    Where-Object {
        $_.FullName -notmatch '\\LOGS\\' -and
        $_.FullName -notmatch '\\Trace\\' -and
        $_.FullName -notmatch '\\LIMS\\' -and
        $_.FullName -notmatch '\\exchangAPI\\' -and
        $_.Name -ne 'BRAVO.config.ps1'
    }

$hasErrors = $false

foreach ($file in $files) {
    $tokens = $null
    $errors = $null

    [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$errors
    ) | Out-Null

    if ($errors -and $errors.Count -gt 0) {
        $hasErrors = $true
        Write-Host "Syntax errors in: $($file.FullName)" -ForegroundColor Red
        $errors | Format-List *
    }
    else {
        Write-Host "OK: $($file.FullName)" -ForegroundColor Green
    }
}

if ($hasErrors) {
    exit 1
}

Write-Host "All PowerShell files parsed successfully." -ForegroundColor Green