# ==============================================================================
# BRAVO.ArchivLims.Logging.ps1
# Автоматично винесені функції з BRAVO_ARCHIV_LIMS.ps1
# ==============================================================================

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [int]$SeparatorLength = 100,
        [switch]$NoTimestamp,
        [switch]$LogOnly
    )

    $logLevels = @{"DEBUG"=0; "INFO"=1; "WARNING"=2; "ERROR"=3; "SUCCESS"=4}

    $currentLogLevel = if ($global:LogLevel -and $logLevels.ContainsKey($global:LogLevel)) {
        $logLevels[$global:LogLevel]
    } else { 1 }

    $messageLevel = if ($logLevels.ContainsKey($Level)) { $logLevels[$Level] } else { 1 }
    if ($messageLevel -lt $currentLogLevel) { return }
    if (-not $global:logFile) { return }

    $separator = "─" * 92

    function Write-ArchivLogLine {
        param([string]$Line)
        try {
            $logDir = Split-Path $global:logFile -Parent
            if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
            $Line | Out-File -FilePath $global:logFile -Append -Encoding UTF8 -ErrorAction SilentlyContinue
        } catch { }
    }

    function Write-ArchivLogSeparator {
        if ($script:ArchivLimsSuppressNextSeparator) {
            $script:ArchivLimsSuppressNextSeparator = $false
            return
        }
        if ($script:ArchivLimsLastLogWasSeparator) { return }
        Write-ArchivLogLine -Line $separator
        $script:ArchivLimsLastLogWasSeparator = $true
    }

    if ([string]::IsNullOrWhiteSpace($Message)) { return }

    if ($Message -match '^={10,}$' -or $Message -eq '=' -or $Message -eq '===') {
        Write-ArchivLogSeparator
        return
    }

    if ($Message -match '^===\s*(.+?)\s*===$') {
        $header = $Matches[1].Trim()
        Write-ArchivLogSeparator
        Write-ArchivLogLine -Line $header
        $script:ArchivLimsLastLogWasSeparator = $false
        $script:ArchivLimsSuppressNextSeparator = $true
        return
    }

    if ($Message -match '^\[(ARC|SYN|NET|SFTP|DEL|SUM)\]\s*(.+)$') {
        $header = $Matches[2].Trim()
        Write-ArchivLogSeparator
        Write-ArchivLogLine -Line $header
        $script:ArchivLimsLastLogWasSeparator = $false
        $script:ArchivLimsSuppressNextSeparator = $true
        return
    }

    if ($Message -match '^---\s*(.+?)\s*---$') {
        $header = $Matches[1].Trim()
        Write-ArchivLogSeparator
        Write-ArchivLogLine -Line $header
        $script:ArchivLimsLastLogWasSeparator = $false
        $script:ArchivLimsSuppressNextSeparator = $true
        return
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Write-ArchivLogLine -Line $logEntry
    $script:ArchivLimsLastLogWasSeparator = $false
    $script:ArchivLimsSuppressNextSeparator = $false
}
function Write-ConsoleSeparator {
    Write-Host ("─" * 92) -ForegroundColor DarkGray
}

function Write-SectionHeader {
    param([string]$Title)

    Write-ConsoleSeparator
    Write-Host $Title -ForegroundColor Cyan
}

function Write-CompactResult {
    param(
        [string]$Icon,
        [string]$Label,
        [string]$Detail,
        [string]$Status,
        [string]$Color = "Gray"
    )

    $labelPadded = Format-ConsoleText -Text $Label -Width 17
    $detailPadded = Format-ConsoleText -Text $Detail -Width 30
    Write-Host " $Icon $labelPadded $detailPadded $Status" -ForegroundColor $Color
}

function Format-SizeMB {
    param(
        [double]$SizeMB,
        [int]$Width = 7,
        [int]$Decimals = 1
    )

    return [string]::Format(
        [System.Globalization.CultureInfo]::InvariantCulture,
        "{0,$Width`:F$Decimals} MB",
        $SizeMB
    )
}

function Format-ConsoleText {
    param(
        [string]$Text,
        [int]$Width
    )

    if ($Text.Length -gt $Width) {
        return "...$($Text.Substring($Text.Length - $Width + 3))"
    }

    return $Text.PadRight($Width)
}

function Get-PackageWord {
    param([int]$Count)

    $lastTwoDigits = $Count % 100
    $lastDigit = $Count % 10

    if ($lastTwoDigits -ge 11 -and $lastTwoDigits -le 14) { return "комплектів" }
    if ($lastDigit -eq 1) { return "комплект" }
    if ($lastDigit -ge 2 -and $lastDigit -le 4) { return "комплекти" }
    return "комплектів"
}

function Get-FileWord {
    param([int]$Count)

    $lastTwoDigits = $Count % 100
    $lastDigit = $Count % 10

    if ($lastTwoDigits -ge 11 -and $lastTwoDigits -le 14) { return "файлів" }
    if ($lastDigit -eq 1) { return "файл" }
    if ($lastDigit -ge 2 -and $lastDigit -le 4) { return "файли" }
    return "файлів"
}

