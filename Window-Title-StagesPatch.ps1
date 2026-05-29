param(
    [string]$TargetPath = ".\ARCHIV_VETOFFICE.ps1"
)

$ErrorActionPreference = "Stop"

function Write-Info($m) { Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "[OK]   $m" -ForegroundColor Green }
function Write-Warn($m) { Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Err($m)  { Write-Host "[ERR]  $m" -ForegroundColor Red }

$TargetPath = [System.IO.Path]::GetFullPath($TargetPath)

if (-not (Test-Path -LiteralPath $TargetPath)) {
    Write-Err "Target file not found: $TargetPath"
    exit 1
}

Write-Info "Target: $TargetPath"

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupPath = "$TargetPath.window_title_stages_bak_$timestamp"
Copy-Item -LiteralPath $TargetPath -Destination $backupPath -Force
Write-Ok "Backup created: $backupPath"

$content = Get-Content -LiteralPath $TargetPath -Raw
$original = $content

# Remove previous copy of this patch block, if any.
$content = [regex]::Replace(
    $content,
    '(?s)\r?\n?# >>> WINDOW TITLE STAGES PATCH: BEGIN.*?# <<< WINDOW TITLE STAGES PATCH: END\r?\n?',
    "`r`n"
)

$titleFunction = @'
# >>> WINDOW TITLE STAGES PATCH: BEGIN
function Set-ArchivWindowTitle {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Stage
    )

    try {
        $Host.UI.RawUI.WindowTitle = "ARCHIV VETOFFICE v$ScriptVersion | $Stage"
    } catch {
        # Window title is best-effort only.
    }
}
# <<< WINDOW TITLE STAGES PATCH: END

'@

# Insert helper before main logic section.
$mainMarker = '# ОСНОВНА ЛОГІКА'
if ($content -notmatch [regex]::Escape('function Set-ArchivWindowTitle')) {
    if ($content.Contains($mainMarker)) {
        $content = $content.Replace($mainMarker, $titleFunction + $mainMarker)
        Write-Ok "Inserted Set-ArchivWindowTitle function."
    } else {
        Write-Err "Could not find main logic marker."
        Write-Err "File was not modified. Backup remains: $backupPath"
        exit 1
    }
}

function Add-AfterOnce {
    param(
        [string]$Text,
        [string]$Find,
        [string]$Insert
    )

    if ($Text.Contains($Insert.Trim())) {
        return $Text
    }

    if (-not $Text.Contains($Find)) {
        Write-Warn "Marker not found: $Find"
        return $Text
    }

    return $Text.Replace($Find, $Find + "`r`n" + $Insert)
}

function Add-BeforeOnce {
    param(
        [string]$Text,
        [string]$Find,
        [string]$Insert
    )

    if ($Text.Contains($Insert.Trim())) {
        return $Text
    }

    if (-not $Text.Contains($Find)) {
        Write-Warn "Marker not found: $Find"
        return $Text
    }

    return $Text.Replace($Find, $Insert + "`r`n" + $Find)
}

# Start and path check.
$content = Add-AfterOnce -Text $content `
    -Find 'function Main {' `
    -Insert '    Set-ArchivWindowTitle -Stage "Запуск скрипта"'

$content = Add-BeforeOnce -Text $content `
    -Find '    Write-Log "=== ПЕРЕВIРКА НЕОБХIДНИХ ШЛЯХIВ ==="' `
    -Insert '    Set-ArchivWindowTitle -Stage "Перевiрка шляхiв"'

# Archive/hash stages inside foreach.
$content = Add-AfterOnce -Text $content `
    -Find '    foreach ($archive in $archives) {' `
    -Insert '        Set-ArchivWindowTitle -Stage "Архiвацiя $($archive.Type)"'

$content = Add-BeforeOnce -Text $content `
    -Find '            Write-Log "--- СТВОРЕННЯ ХЕШУ $($archive.Type) ---"' `
    -Insert '            Set-ArchivWindowTitle -Stage "SHA512 $($archive.Type)"'

# SFTP / network copy / BAZA / cleanup / finish.
$content = Add-BeforeOnce -Text $content `
    -Find '    if ($enableSFTPUpload) {' `
    -Insert '    Set-ArchivWindowTitle -Stage "SFTP"'

$content = Add-BeforeOnce -Text $content `
    -Find '    if ($enableNetworkCopy) {' `
    -Insert '    Set-ArchivWindowTitle -Stage "Копiювання в мережу"'

$content = Add-BeforeOnce -Text $content `
    -Find '    Write-Log "=== СИНХРОНІЗАЦІЯ ФАЙЛІВ BAZA ==="' `
    -Insert '    Set-ArchivWindowTitle -Stage "Синхронiзацiя BAZA"'

$content = Add-BeforeOnce -Text $content `
    -Find '    if ($enableArchiveDeletion) {' `
    -Insert '    Set-ArchivWindowTitle -Stage "Очищення старих архiвiв"'

$content = Add-BeforeOnce -Text $content `
    -Find '    Write-Log "=== ОЧИЩЕННЯ СТАРИХ ЛОГIВ ==="' `
    -Insert '    Set-ArchivWindowTitle -Stage "Очищення старих логiв"'

$content = Add-BeforeOnce -Text $content `
    -Find '    Write-Log "=== ЗАВЕРШЕННЯ РОБОТИ СКРИПТА ==="' `
    -Insert '    Set-ArchivWindowTitle -Stage "Завершено"'

if ($content -eq $original) {
    Write-Warn "No changes were made."
    exit 0
}

# Save as UTF-8 with BOM for Windows PowerShell 5.1.
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($TargetPath, $content, $utf8Bom)

Write-Info "Checking PowerShell syntax..."
$parseErrors = $null
[void][System.Management.Automation.PSParser]::Tokenize((Get-Content -LiteralPath $TargetPath -Raw), [ref]$parseErrors)

if ($parseErrors -and $parseErrors.Count -gt 0) {
    Write-Err "Syntax errors found. Restore from backup if needed: $backupPath"
    $parseErrors | Format-List
    exit 2
}

Write-Ok "Syntax OK."
Write-Host ""
Write-Host "Expected window titles:" -ForegroundColor Cyan
Write-Host "  ARCHIV VETOFFICE v2.1 | Перевiрка шляхiв"
Write-Host "  ARCHIV VETOFFICE v2.1 | Архiвацiя VETOFFICE"
Write-Host "  ARCHIV VETOFFICE v2.1 | SHA512 VETOFFICE"
Write-Host "  ARCHIV VETOFFICE v2.1 | Архiвацiя BLOG"
Write-Host "  ARCHIV VETOFFICE v2.1 | SHA512 BLOG"
Write-Host "  ARCHIV VETOFFICE v2.1 | Завершено"
Write-Host ""
Write-Host "Test:" -ForegroundColor Cyan
Write-Host "  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ARCHIV_VETOFFICE.ps1"
