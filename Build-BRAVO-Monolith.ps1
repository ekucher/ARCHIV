#requires -version 5.1
<#
.SYNOPSIS
    Builds deployable BRAVO_MAINTENANCE.ps1 from modular source files.

.DESCRIPTION
    Keep development modular in src\ and deploy one generated monolith to servers.

    Default layout:
        src\
          00-Header.ps1
          05-Params.ps1
          10-Config.ps1
          20-Logging.ps1
          30-Credentials.ps1
          40-Slack.ps1
          50-ProgressState.ps1
          60-Scheduler.ps1
          70-Archive.ps1
          80-HealthCheck.ps1
          90-Maintenance.ps1
          99-Main.ps1
          BRAVO.build.json

        dist\
          BRAVO_MAINTENANCE.ps1

.EXAMPLE
    .\Build-BRAVO-Monolith.ps1 -Clean -CreateSha512

.EXAMPLE
    .\Build-BRAVO-Monolith.ps1 -OutputPath .\BRAVO_MAINTENANCE.ps1

.EXAMPLE
    .\Build-BRAVO-Monolith.ps1 -Clean -CreateSha512 -DeployPath "\\server\share\BRAVO_MAINTENANCE.ps1"
#>

[CmdletBinding()]
param(
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$SourceDir = "src",
    [string]$ManifestPath = "src\BRAVO.build.json",
    [string]$OutputPath = "dist\BRAVO_MAINTENANCE.ps1",
    [string]$DeployPath = "",
    [string]$Version = "",
    [switch]$Clean,
    [switch]$CreateSha512,
    [switch]$NoSyntaxCheck,
    [switch]$StrictManifest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-BravoBuildPath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path -Path $BasePath -ChildPath $Path))
}

function Invoke-BravoGit {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$Fallback = ""
    )

    try {
        $value = & git @Arguments 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
            return ([string]$value).Trim()
        }
    }
    catch {
        # Git is optional for local/server builds.
    }

    return $Fallback
}

function Get-BravoBuildVersion {
    param([string]$ExplicitVersion)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitVersion)) {
        return $ExplicitVersion
    }

    $tag = Invoke-BravoGit -Arguments @("describe", "--tags", "--always", "--dirty") -Fallback ""
    if (-not [string]::IsNullOrWhiteSpace($tag)) {
        return $tag
    }

    return "dev-" + (Get-Date -Format "yyyyMMdd-HHmmss")
}

function ConvertTo-BravoLf {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) {
        return ""
    }

    return (($Text -replace "`r`n", "`n") -replace "`r", "`n")
}

function Write-BravoUtf8BomFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $normalized = ConvertTo-BravoLf -Text $Content
    $crlf = $normalized -replace "`n", "`r`n"

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($Path, $crlf, $utf8Bom)
}

function Read-BravoBuildManifest {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $json = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($json)) {
        throw "Build manifest is empty: $Path"
    }

    return $json | ConvertFrom-Json
}

function Get-BravoSourceFiles {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRootFullPath,
        [Parameter(Mandatory = $true)][string]$SourceDirFullPath,
        [Parameter(Mandatory = $true)][string]$ManifestFullPath,
        [switch]$StrictManifest
    )

    $manifest = Read-BravoBuildManifest -Path $ManifestFullPath

    if ($manifest -and $manifest.files) {
        $files = @()

        foreach ($entry in @($manifest.files)) {
            $relativePath = [string]$entry
            if ([string]::IsNullOrWhiteSpace($relativePath)) {
                continue
            }

            $fullPath = Resolve-BravoBuildPath -BasePath $ProjectRootFullPath -Path $relativePath

            if (-not (Test-Path -LiteralPath $fullPath)) {
                throw "Manifest file not found: $relativePath -> $fullPath"
            }

            $files += Get-Item -LiteralPath $fullPath
        }

        return $files
    }

    if ($StrictManifest) {
        throw "Manifest not found or does not contain files[]: $ManifestFullPath"
    }

    if (-not (Test-Path -LiteralPath $SourceDirFullPath)) {
        throw "Source directory not found: $SourceDirFullPath"
    }

    return Get-ChildItem -LiteralPath $SourceDirFullPath -Filter "*.ps1" -File |
        Where-Object {
            $_.Name -notlike "*.Tests.ps1" -and
            $_.Name -notlike "Build-*" -and
            $_.Name -notlike "*.generated.ps1"
        } |
        Sort-Object Name
}

function Test-BravoPowerShellSyntax {
    param([Parameter(Mandatory = $true)][string]$Path)

    $tokens = $null
    $parseErrors = $null

    [System.Management.Automation.Language.Parser]::ParseFile(
        $Path,
        [ref]$tokens,
        [ref]$parseErrors
    ) | Out-Null

    if ($parseErrors -and $parseErrors.Count -gt 0) {
        Write-Host ""
        Write-Host "Syntax errors found:" -ForegroundColor Red

        foreach ($err in $parseErrors) {
            Write-Host ("  Line {0}, Column {1}: {2}" -f `
                $err.Extent.StartLineNumber,
                $err.Extent.StartColumnNumber,
                $err.Message) -ForegroundColor Red
        }

        throw "Syntax validation failed: $Path"
    }

    Write-Host "Syntax OK: $Path" -ForegroundColor Green
}

function New-BravoSha512File {
    param([Parameter(Mandatory = $true)][string]$Path)

    $hash = Get-FileHash -LiteralPath $Path -Algorithm SHA512
    $shaPath = "$Path.sha512"
    $line = "$($hash.Hash)  $([System.IO.Path]::GetFileName($Path))"

    Write-BravoUtf8BomFile -Path $shaPath -Content ($line + "`n")
    Write-Host "SHA512 created: $shaPath" -ForegroundColor Green
}

$projectRootFull = [System.IO.Path]::GetFullPath($ProjectRoot)
$sourceDirFull = Resolve-BravoBuildPath -BasePath $projectRootFull -Path $SourceDir
$manifestFull = Resolve-BravoBuildPath -BasePath $projectRootFull -Path $ManifestPath
$outputFull = Resolve-BravoBuildPath -BasePath $projectRootFull -Path $OutputPath

Write-Host "Project root: $projectRootFull" -ForegroundColor Cyan
Write-Host "Source dir:   $sourceDirFull" -ForegroundColor Cyan
Write-Host "Manifest:     $manifestFull" -ForegroundColor Cyan
Write-Host "Output:       $outputFull" -ForegroundColor Cyan

if ($Clean) {
    $outputDirToClean = Split-Path -Path $outputFull -Parent
    if (Test-Path -LiteralPath $outputDirToClean) {
        Write-Host "Cleaning output directory: $outputDirToClean" -ForegroundColor Yellow
        Remove-Item -LiteralPath $outputDirToClean -Recurse -Force
    }
}

$outputDir = Split-Path -Path $outputFull -Parent
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
}

$sourceFiles = @(Get-BravoSourceFiles `
    -ProjectRootFullPath $projectRootFull `
    -SourceDirFullPath $sourceDirFull `
    -ManifestFullPath $manifestFull `
    -StrictManifest:$StrictManifest)

if ($sourceFiles.Count -eq 0) {
    throw "No source files found."
}

$versionValue = Get-BravoBuildVersion -ExplicitVersion $Version
$commitValue = Invoke-BravoGit -Arguments @("rev-parse", "--short", "HEAD") -Fallback "unknown"
$branchValue = Invoke-BravoGit -Arguments @("rev-parse", "--abbrev-ref", "HEAD") -Fallback "unknown"
$buildTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")

$parts = New-Object System.Collections.Generic.List[string]

$header = @"
##########
# BravoSoft BRAVO Maintenance
# Generated deployable monolith
#
# DO NOT EDIT THIS FILE DIRECTLY IF USING MODULAR SOURCE.
# Edit files in src\ and run Build-BRAVO-Monolith.ps1.
#
# Build version: $versionValue
# Git branch:    $branchValue
# Git commit:    $commitValue
# Build time:    $buildTime
##########

"@

[void]$parts.Add($header)

foreach ($file in $sourceFiles) {
    $relative = [System.IO.Path]::GetRelativePath($projectRootFull, $file.FullName)
    $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    $content = ConvertTo-BravoLf -Text $content

    if ([string]::IsNullOrWhiteSpace($content)) {
        Write-Host "Skipping empty source file: $relative" -ForegroundColor Yellow
        continue
    }

    Write-Host "Adding: $relative" -ForegroundColor Gray

    [void]$parts.Add(@"

# ==================================================================================================
# BEGIN MODULE: $relative
# ==================================================================================================

"@)

    [void]$parts.Add($content.TrimEnd() + "`n")

    [void]$parts.Add(@"

# ==================================================================================================
# END MODULE: $relative
# ==================================================================================================

"@)
}

$builtContent = ($parts.ToArray() -join "")
Write-BravoUtf8BomFile -Path $outputFull -Content $builtContent

Write-Host ""
Write-Host "Built monolith: $outputFull" -ForegroundColor Green
Write-Host ("Included files: {0}" -f $sourceFiles.Count) -ForegroundColor Green

if (-not $NoSyntaxCheck) {
    Test-BravoPowerShellSyntax -Path $outputFull
}
else {
    Write-Host "Syntax check skipped." -ForegroundColor Yellow
}

if ($CreateSha512) {
    New-BravoSha512File -Path $outputFull
}

if (-not [string]::IsNullOrWhiteSpace($DeployPath)) {
    $deployFull = Resolve-BravoBuildPath -BasePath $projectRootFull -Path $DeployPath
    $deployDir = Split-Path -Path $deployFull -Parent

    if (-not (Test-Path -LiteralPath $deployDir)) {
        New-Item -Path $deployDir -ItemType Directory -Force | Out-Null
    }

    Copy-Item -LiteralPath $outputFull -Destination $deployFull -Force
    Write-Host "Deployed monolith to: $deployFull" -ForegroundColor Green

    if ($CreateSha512 -and (Test-Path -LiteralPath "$outputFull.sha512")) {
        Copy-Item -LiteralPath "$outputFull.sha512" -Destination "$deployFull.sha512" -Force
        Write-Host "Deployed SHA512 to: $deployFull.sha512" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Build completed successfully." -ForegroundColor Green
