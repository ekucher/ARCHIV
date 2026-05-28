##########
# BravoSoft
# Author: Evgeniy Kucher
# Version: 1.2, 2025-10-04 - Slack версія з оновленим логуванням
##########

# Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass –Force

# ===== SETTINGS FROM BRAVO.config.ps1 =====
$global:ObjectName = [string](Get-BravoConfigValue -Name "ObjectName" -Default "")

$BravoServiceName = [string](Get-BravoConfigValue -Name "BravoServiceName" -Default "BRAVO")
$ExchangAPIServiceName = [string](Get-BravoConfigValue -Name "ExchangAPIServiceName" -Default "exchangAPI")
$ExchangAPIProcessName = [string](Get-BravoConfigValue -Name "ExchangAPIProcessName" -Default "exchangAPI")

$ArchivePrefix = [string](Get-BravoConfigValue -Name "ArchivePrefix" -Default "")
$ArchivePasswordCredentialTarget = [string](Get-BravoConfigValue -Name "ArchivePasswordCredentialTarget" -Default "BRAVO/ArchivePassword")
$SlackWebhookCredentialTarget = [string](Get-BravoConfigValue -Name "SlackWebhookCredentialTarget" -Default "BRAVO/SlackWebhookUrl")

# Archive password mode is needed before -SetupCredentials so the setup wizard can decide
# whether archive password should be requested according to BRAVO.config.ps1.
$ArchivePasswordEnabled = [string](Get-BravoConfigValue -Name "ArchivePasswordEnabled" -Default "on")
$ArchivePasswordEncryptHeaders = [string](Get-BravoConfigValue -Name "ArchivePasswordEncryptHeaders" -Default "on")
$ArchivePasswordEncryptHeaders = if ([string]::IsNullOrWhiteSpace($ArchivePasswordEncryptHeaders)) { "on" } else { $ArchivePasswordEncryptHeaders.ToLowerInvariant() }

if ($ArchivePasswordEncryptHeaders -notin @("on", "off")) {
    Write-Host "ERROR: ArchivePasswordEncryptHeaders must be 'on' or 'off'. Current value: $ArchivePasswordEncryptHeaders" -ForegroundColor Red
    exit 1
}
$ArchivePasswordEnabled = if ([string]::IsNullOrWhiteSpace($ArchivePasswordEnabled)) { "on" } else { $ArchivePasswordEnabled.ToLowerInvariant() }

if ($ArchivePasswordEnabled -notin @("on", "off")) {
    Write-Host "ERROR: ArchivePasswordEnabled must be 'on' or 'off'. Current value: $ArchivePasswordEnabled" -ForegroundColor Red
    exit 1
}

# Slack mode is needed before -SetupCredentials so the setup wizard can decide
# whether Slack webhook URL should be requested.
$SlackMode = [string](Get-BravoConfigValue -Name "SlackMode" -Default "errors_only")
# Progress state / power-loss recovery
$ProgressStateEnabled = [string](Get-BravoConfigValue -Name "ProgressStateEnabled" -Default "on")
$ProgressStateMaxAgeHours = [int](Get-BravoConfigValue -Name "ProgressStateMaxAgeHours" -Default 72)
$ProgressStateAutoResumeForScheduler = [string](Get-BravoConfigValue -Name "ProgressStateAutoResumeForScheduler" -Default "on")

if ($SetupCredentials) {
    Invoke-BravoCredentialSetup `
        -ArchivePasswordTarget $ArchivePasswordCredentialTarget `
        -SlackWebhookTarget $SlackWebhookCredentialTarget `
        -SlackMode $SlackMode `
        -ArchivePasswordEnabled $ArchivePasswordEnabled
    exit 0
}

if ($InstallScheduledTask) {
    Install-BravoScheduledTask `
        -TaskName $TaskName `
        -TaskUserName $TaskUserName `
        -At $TaskTime `
        -DaysOfWeek $TaskDaysOfWeek `
        -ScriptArguments "" `
        -AddTaskUserToAdministrators:$AddTaskUserToAdministrators `
        -ResetTaskUserPassword:$ResetTaskUserPassword `
        -SkipTaskUserCredentialBootstrap:$SkipTaskUserCredentialBootstrap `
        -ArchivePasswordEnabled $ArchivePasswordEnabled
    exit 0
}

$ArchivePasswordConfigValue = [string](Get-BravoConfigValue -Name "ArchivePassword" -Default "")
$ArchivePassword = ""

if ($ArchivePasswordEnabled -eq "on") {
    $ArchivePassword = [string](Get-BravoSecret `
        -Name "ArchivePassword" `
        -Target $ArchivePasswordCredentialTarget `
        -ConfigValue $ArchivePasswordConfigValue)

    if ([string]::IsNullOrWhiteSpace($ArchivePassword)) {
        $canPromptForArchivePassword = $true

        try {
            if ([Console]::IsInputRedirected) {
                $canPromptForArchivePassword = $false
            }
        }
        catch {
            $canPromptForArchivePassword = $false
        }

        if (-not [Environment]::UserInteractive) {
            $canPromptForArchivePassword = $false
        }

        # Do not prompt when running under the dedicated scheduler user.
        if ($env:USERNAME -ieq $TaskUserName) {
            $canPromptForArchivePassword = $false
        }

        if ($canPromptForArchivePassword) {
            Write-Warning "ArchivePasswordEnabled is 'on', but archive password is not saved in Windows Credential Manager and is empty in config."
            $saveArchivePasswordRuntime = Read-Host "Save archive password now? Type YES to save"

            if ($saveArchivePasswordRuntime -eq "YES") {
                Save-BravoSecretInteractive `
                    -Target $ArchivePasswordCredentialTarget `
                    -UserName "BRAVO" `
                    -Prompt "Archive password"

                $archiveCredential = Get-BravoWindowsCredential -Target $ArchivePasswordCredentialTarget
                if ($archiveCredential -and -not [string]::IsNullOrWhiteSpace($archiveCredential.Secret)) {
                    $ArchivePassword = [string]$archiveCredential.Secret
                    Write-Host "Archive password saved and loaded for current run." -ForegroundColor Green
                }
            }
        }
        else {
            throw "ArchivePasswordEnabled is 'on', but archive password is missing and this run is non-interactive or running as scheduler user '$TaskUserName'. Run .\BRAVO_MAINTENANCE.ps1 -SetupCredentials interactively or reinstall the task with credential bootstrap."
        }
    }

    if ([string]::IsNullOrWhiteSpace($ArchivePassword)) {
        throw "ArchivePasswordEnabled is 'on', but archive password was not provided. Archive creation cannot continue."
    }
}
else {
    Write-Host "ArchivePasswordEnabled is 'off'. Archives will be created without password." -ForegroundColor Yellow
}

# SlackMode loaded earlier before -SetupCredentials
$SlackWebhookUrlConfigValue = [string](Get-BravoConfigValue -Name "SlackWebhookUrl" -Default "")
$SlackWebhookUrl = [string](Get-BravoSecret `
    -Name "SlackWebhookUrl" `
    -Target $SlackWebhookCredentialTarget `
    -ConfigValue $SlackWebhookUrlConfigValue)

# If Slack is enabled but webhook URL is missing, offer to save it during an interactive manual run.
$normalizedSlackModeRuntime = if ([string]::IsNullOrWhiteSpace($SlackMode)) {
    "none"
}
else {
    $SlackMode.ToLowerInvariant()
}

$slackEnabledRuntime = ($normalizedSlackModeRuntime -notin @("none", "off"))

if ($slackEnabledRuntime -and [string]::IsNullOrWhiteSpace($SlackWebhookUrl)) {
    $canPromptForSlackWebhook = $true

    try {
        if ([Console]::IsInputRedirected) {
            $canPromptForSlackWebhook = $false
        }
    }
    catch {
        $canPromptForSlackWebhook = $false
    }

    if (-not [Environment]::UserInteractive) {
        $canPromptForSlackWebhook = $false
    }

    # Do not prompt when running under the dedicated scheduler user.
    if ($env:USERNAME -ieq $TaskUserName) {
        $canPromptForSlackWebhook = $false
    }

    if ($canPromptForSlackWebhook) {
        Write-Warning "SlackMode is '$SlackMode', but Slack webhook URL is not saved in Windows Credential Manager and is empty in config."
        $saveSlackRuntime = Read-Host "Save Slack webhook URL now? Type YES to save"

        if ($saveSlackRuntime -eq "YES") {
            Save-BravoSecretInteractive `
                -Target $SlackWebhookCredentialTarget `
                -UserName "BRAVO" `
                -Prompt "Slack webhook URL"

            $slackCredential = Get-BravoWindowsCredential -Target $SlackWebhookCredentialTarget
            if ($slackCredential -and -not [string]::IsNullOrWhiteSpace($slackCredential.Secret)) {
                $SlackWebhookUrl = [string]$slackCredential.Secret
                Write-Host "Slack webhook URL saved and loaded for current run." -ForegroundColor Green
            }
        }
        else {
            Write-Warning "Slack webhook URL was not saved. Slack will be disabled for this run."
        }
    }
    else {
        Write-Warning "SlackMode is '$SlackMode', but Slack webhook URL is missing and this run is non-interactive or running as scheduler user '$TaskUserName'. Run .\BRAVO_MAINTENANCE.ps1 -SetupCredentials interactively or reinstall the task with credential bootstrap."
    }
}

$SevenZipArchiveArgs = @(
    Get-BravoConfigValue -Name "SevenZipArchiveArgs" -Required
)

$SevenZipExtractArgs = @(
    Get-BravoConfigValue -Name "SevenZipExtractArgs" -Required
)

$RestoreDay = [int](Get-BravoConfigValue -Name "RestoreDay" -Default 7)
$RestoreTime = [string](Get-BravoConfigValue -Name "RestoreTime" -Default "23:00")

$ARCHIVE_RETENTION_DAYS = [int](Get-BravoConfigValue -Name "ArchiveRetentionDays" -Default 14)
$RESTORE_ARCHIVES_KEEP_COUNT = [int](Get-BravoConfigValue -Name "RestoreArchivesKeepCount" -Default 1)
$LOG_RETENTION_DAYS = [int](Get-BravoConfigValue -Name "LogRetentionDays" -Default 180)

$MIN_FREE_SPACE = [double](Get-BravoConfigValue -Name "MinFreeSpaceGB" -Default 10)

$MaxMdFileSizeGB = [double](Get-BravoConfigValue -Name "MaxMdFileSizeGB" -Default 1.5)
$MAX_MD_FILE_SIZE = [int64]($MaxMdFileSizeGB * 1GB)

$ExcludedMdSizeCheckFiles = @(
    Get-BravoConfigValue -Name "ExcludedMdSizeCheckFiles" -Default @()
)

$BRAVO_WEB_DIR = [string](Get-BravoConfigValue -Name "BravoWebDir" -Default "D:\Br-a-vo.web")

$AutoShutdownDefault = [string](Get-BravoConfigValue -Name "AutoShutdown" -Default "off")
$ShutdownTimeout = [int](Get-BravoConfigValue -Name "ShutdownTimeout" -Default 60)

$ArchivLimsDefault = [string](Get-BravoConfigValue -Name "ArchivLims" -Default "off")

# SlackMode and SlackWebhookUrl are loaded through Windows Credential Manager aware logic above.

$LogLevel = [string](Get-BravoConfigValue -Name "LogLevel" -Default "INFO")
$global:LogLevel = $LogLevel

# Disable Slack automatically if webhook URL is empty
if ([string]::IsNullOrWhiteSpace($SlackWebhookUrl)) {
    if ($SlackMode.ToLowerInvariant() -notin @("none", "off")) {
        Write-Warning "SlackMode is '$SlackMode', but SlackWebhookUrl is empty or not found in Windows Credential Manager. Slack will be disabled."
    }
    $SlackMode = "none"
}

# Command line parameters override config values
if ($PSBoundParameters.ContainsKey("AutoShutdown") -and -not [string]::IsNullOrWhiteSpace($AutoShutdown)) {
    $AutoShutdown = $AutoShutdown.ToLower()
}
else {
    $AutoShutdown = $AutoShutdownDefault.ToLower()
}

if ($AutoShutdown -notin @("on", "off")) {
    Write-Host "ERROR: AutoShutdown must be 'on' or 'off'. Current value: $AutoShutdown" -ForegroundColor Red
    exit 1
}

$script:EnableAutoShutdown = ($AutoShutdown -eq "on")

if ($PSBoundParameters.ContainsKey("ArchivLims") -and -not [string]::IsNullOrWhiteSpace($ArchivLims)) {
    $ArchivLims = $ArchivLims.ToLower()
}
else {
    $ArchivLims = $ArchivLimsDefault.ToLower()
}

if ($ArchivLims -notin @("on", "off")) {
    Write-Host "ERROR: ArchivLims must be 'on' or 'off'. Current value: $ArchivLims" -ForegroundColor Red
    exit 1
}

$script:EnableArchivLims = ($ArchivLims -eq "on")

# Elevate to administrator if needed
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    $elevatedArgs = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $PSCommandPath
    )

    foreach ($parameterName in $PSBoundParameters.Keys) {
        $parameterValue = $PSBoundParameters[$parameterName]

        if ($parameterValue -is [System.Management.Automation.SwitchParameter]) {
            if ($parameterValue.IsPresent) {
                $elevatedArgs += "-$parameterName"
            }

            continue
        }

        if ($parameterValue -is [array]) {
            foreach ($item in $parameterValue) {
                $elevatedArgs += @("-$parameterName", [string]$item)
            }

            continue
        }

        if ($null -ne $parameterValue) {
            $elevatedArgs += @("-$parameterName", [string]$parameterValue)
        }
    }

    Start-Process -FilePath "powershell.exe" `
        -ArgumentList $elevatedArgs `
        -WorkingDirectory $PSScriptRoot `
        -Verb RunAs

    exit
}

# Enforce modern security protocol
Set-BravoTlsProtocol

# Clear console
Clear-Host

# Apache service detection
$ApacheService = Get-Service -Name "Apache2.4" -ErrorAction SilentlyContinue
$ApacheServiceExists = ($ApacheService -ne $null)

# Archiver parameters
$arcCommonParams = @($SevenZipArchiveArgs)
if ($ArchivePasswordEnabled -eq "on" -and -not [string]::IsNullOrWhiteSpace($ArchivePassword)) {
    $arcCommonParams += "-p$ArchivePassword"

    if ($ArchivePasswordEncryptHeaders -eq "on") {
        $arcCommonParams += "-mhe=on"
    }
}

# ===== GLOBAL RUNTIME VARIABLES =====
$global:ScriptStartTime = [DateTime]::Now
$global:SlackMessageBuffer = [System.Collections.Generic.List[string]]::new()
$global:CriticalErrors = $false
$global:CriticalErrorsList = [System.Collections.Generic.List[string]]::new()
$global:criticalErrorOccurred = $false

# Визначаємо режим Slack (НОВА ЛОГІКА) - ЗМІНЕНО: використовуємо глобальне значення за замовчуванням
if ($DisableAllSlack) {
    $script:SlackMode = "none"
    Write-Host "Режим Slack: ВИМКНЕНО (none)" -ForegroundColor Yellow
} elseif ($EnableAllSlack) {
    $script:SlackMode = "all" 
    Write-Host "Режим Slack: УСІ ПОВІДОМЛЕННЯ (all)" -ForegroundColor Green
} else {
    $script:SlackMode = $SlackMode  # Використовуємо глобальне значення за замовчуванням
    #Write-Host "Режим Slack: ВИМКНЕНО (none) - за замовчуванням" -ForegroundColor Yellow
}
# Перетворення числового дня в об'єкт DayOfWeek
$restoreDayMap = @{
    1 = [DayOfWeek]::Monday
    2 = [DayOfWeek]::Tuesday
    3 = [DayOfWeek]::Wednesday
    4 = [DayOfWeek]::Thursday
    5 = [DayOfWeek]::Friday
    6 = [DayOfWeek]::Saturday
    7 = [DayOfWeek]::Sunday
}
$RestoreDayOfWeek = $restoreDayMap[$RestoreDay]
$RestoreDayName = $RestoreDayOfWeek.ToString()
# Перевірка версії ОС
$osVersion = [System.Environment]::OSVersion.Version
if ($osVersion.Major -lt 6 -or ($osVersion.Major -eq 6 -and $osVersion.Minor -lt 3)) {
    Write-Host "ПОМИЛКА: Скрипт вимагає Windows 8.1/Windows Server 2012 R2 або новішої версії" -ForegroundColor Red
    exit 1
}

# Автоматичне визначення каталогу BRAVO_WEB
$ApacheEnabled = $false
$ApacheWebDirExists = $false
$ApacheDetectionMessages = [System.Collections.Generic.List[string]]::new()

$bravoWebCandidates = [System.Collections.Generic.List[string]]::new()

if (-not [string]::IsNullOrWhiteSpace($BRAVO_WEB_DIR)) {
    $bravoWebCandidates.Add($BRAVO_WEB_DIR)
}

$bravoWebCandidates.Add("C:\Br-a-vo.web")
$bravoWebCandidates.Add("D:\Br-a-vo.web")
$bravoWebCandidates.Add("E:\Br-a-vo.web")

$detectedBravoWebDir = $bravoWebCandidates |
    Select-Object -Unique |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1

if ($detectedBravoWebDir) {
    if ($BRAVO_WEB_DIR -ne $detectedBravoWebDir) {
        $ApacheDetectionMessages.Add("Каталог Br-a-vo.web визначено автоматично: $detectedBravoWebDir") | Out-Null
    }

    $BRAVO_WEB_DIR = [string]$detectedBravoWebDir
    $ApacheWebDirExists = $true
}

if ($ApacheServiceExists -and $ApacheWebDirExists) {
    $Apache = "$BRAVO_WEB_DIR\apache\bin\httpd.exe"

    $ApacheExists = Test-Path -LiteralPath $Apache
    $ApacheLogsExist = (Test-Path -LiteralPath "$BRAVO_WEB_DIR\apache\logs") -and (Test-Path -LiteralPath "$BRAVO_WEB_DIR\www\log")
    $ApacheEnabled = $true

    if (-not $ApacheExists) {
        $ApacheDetectionMessages.Add("Apache service знайдено, але httpd.exe не знайдено: $Apache") | Out-Null
    }

    if (-not $ApacheLogsExist) {
        $ApacheDetectionMessages.Add("Apache service знайдено, але лог-директорії Apache/WWW відсутні - обробка логів буде пропущена") | Out-Null
    }
}
elseif ($ApacheServiceExists -and -not $ApacheWebDirExists) {
    $ApacheDetectionMessages.Add("Apache service знайдено, але каталог Br-a-vo.web не знайдено - керування Apache вимкнено") | Out-Null
}

# Автоматичне визначення кореня LIMS
$scriptPath = $PSScriptRoot
if (-not $scriptPath) { $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path }

if ((Split-Path -Leaf $scriptPath) -ne "ARCHIV") {
    $errorMessage = "ПОМИЛКА: Скрипт має запускатись лише з папки ARCHIV!"
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $errorMessage" | Out-File "$env:TEMP\lims_error.log" -Append
    Write-Host $errorMessage -ForegroundColor Red
    exit 1
}

$ROOT_LIMS = Split-Path -Parent $scriptPath
$ExchangAPIExePath = "$ROOT_LIMS\exchangAPI.exe"  # Шлях до exchangAPI.exe

# Інформація про NSSM-службу exchangAPI
$ExchangAPIService = Get-Service -Name $ExchangAPIServiceName -ErrorAction SilentlyContinue
$ExchangAPIServiceExists = ($null -ne $ExchangAPIService)
$ExchangAPIServiceWorkingDir = $null

if ($ExchangAPIServiceExists) {
    $exchangApiNssmPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ExchangAPIServiceName\Parameters"

    if (Test-Path -LiteralPath $exchangApiNssmPath) {
        $exchangApiNssmParams = Get-ItemProperty -LiteralPath $exchangApiNssmPath -ErrorAction SilentlyContinue
        $ExchangAPIServiceWorkingDir = [string]$exchangApiNssmParams.AppDirectory
    }
}

# Похідні шляхи
$MODEL_PATH = "$ROOT_LIMS\Model"
$LOG_DIR = "$ROOT_LIMS\ARCHIV\LOGS"
$TRACE_DIR = "$ROOT_LIMS\ARCHIV\Trace"
$ARC_DIR = "$ROOT_LIMS\ARCHIV\LIMS"
$ARC_PATH = "$ROOT_LIMS\ARCHIV\Tools\7za.exe"   # Шлях до архіватора
$EXCHANGAPI_ARCHIV_DIR = "$ROOT_LIMS\ARCHIV\exchangAPI"

if ($ApacheServiceExists -and $ApacheEnabled) {
    $BRAVO_WEB_ARCHIV_DIR = "$ROOT_LIMS\ARCHIV\Br-a-vo.web"
    $APACHE_LOGS_DIR = "$BRAVO_WEB_DIR\apache\logs"
    $WWW_LOGS_DIR = "$BRAVO_WEB_DIR\www\log"
}

# Переконатися, що директорія логів існує
if (-not (Test-Path $LOG_DIR)) {
    try {
        New-Item -Path $LOG_DIR -ItemType Directory -Force | Out-Null
        Write-Host "Створено директорію для логів: $LOG_DIR" -ForegroundColor Green
    }
    catch {
        Write-Host "Не вдалося створити директорію для логів $LOG_DIR : $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Ініціалізація дати
$currentDate = Get-Date
$NOW = $currentDate.ToString("yyyyMMdd_HHmm")
$YYYY = $currentDate.Year.ToString("0000")
$MM = $currentDate.Month.ToString("00")
$DD = $currentDate.Day.ToString("00")

# Похідні параметри
$isRestoreDay = ($currentDate.DayOfWeek -eq $RestoreDayOfWeek)
$restoreTimeSpan = [TimeSpan]::Parse($RestoreTime)
$isAfterRestoreTime = ($currentDate.TimeOfDay -ge $restoreTimeSpan)

# Визначаємо MARKER_FILE до використання в shouldRestore
$MARKER_FILE = "$LOG_DIR\restore_done_$YYYY$MM$DD.marker"

$shouldRestore = $ForceRestore -or ($isRestoreDay -and $isAfterRestoreTime -and -not (Test-Path $MARKER_FILE))
$restoreReason = if ($ForceRestore) { "Примусово" } else { "$RestoreDayName, після $RestoreTime" }
$CheckSize = -not $DisableSizeCheck

# Похідні файлові шляхи
$ARCH_NAME1 = "${ArchivePrefix}_before_$NOW.mdz"
$ARCH_NAME2 = "${ArchivePrefix}_after_$NOW.mdz"
$LOG_FILE = "$LOG_DIR\script_log_$NOW.txt"
$SIZES_FILE = "$LOG_DIR\file_sizes_before_$NOW.csv"
$TRACE_ARCHIV_DIR = "$TRACE_DIR\$YYYY-$MM-$DD"
# Progress state / power-loss recovery
$STATE_DIR = "$ROOT_LIMS\ARCHIV\STATE"
$PROGRESS_STATE_FILE = Join-Path -Path $STATE_DIR -ChildPath "BRAVO_MAINTENANCE_STATE.json"

$progressMetadata = @{
    NOW = $NOW
    YYYY = $YYYY
    MM = $MM
    DD = $DD
    ARCH_NAME1 = $ARCH_NAME1
    ARCH_NAME2 = $ARCH_NAME2
    LOG_FILE = $LOG_FILE
    SIZES_FILE = $SIZES_FILE
    TRACE_ARCHIV_DIR = $TRACE_ARCHIV_DIR
    MARKER_FILE = $MARKER_FILE
    ROOT_LIMS = $ROOT_LIMS
}

if ($ShowProgressState) {
    Show-BravoProgressState -StatePath $PROGRESS_STATE_FILE
    Wait-BravoInteractiveExit -TaskUserName $TaskUserName -ExitCode 0
    exit 0
}

Initialize-BravoProgressState `
    -StatePath $PROGRESS_STATE_FILE `
    -RunId $NOW `
    -Metadata $progressMetadata `
    -Enabled $ProgressStateEnabled `
    -MaxAgeHours $ProgressStateMaxAgeHours `
    -AutoResumeForScheduler $ProgressStateAutoResumeForScheduler `
    -TaskUserName $TaskUserName `
    -Reset:$ResetProgress `
    -Ignore:$IgnoreProgress

if ($script:BravoProgressStateWasResumed -and $script:BravoProgressState.Metadata) {
    $resumeMetadata = $script:BravoProgressState.Metadata

    if ($resumeMetadata.NOW) { $NOW = [string]$resumeMetadata.NOW }
    if ($resumeMetadata.YYYY) { $YYYY = [string]$resumeMetadata.YYYY }
    if ($resumeMetadata.MM) { $MM = [string]$resumeMetadata.MM }
    if ($resumeMetadata.DD) { $DD = [string]$resumeMetadata.DD }
    if ($resumeMetadata.ARCH_NAME1) { $ARCH_NAME1 = [string]$resumeMetadata.ARCH_NAME1 }
    if ($resumeMetadata.ARCH_NAME2) { $ARCH_NAME2 = [string]$resumeMetadata.ARCH_NAME2 }
    if ($resumeMetadata.LOG_FILE) { $LOG_FILE = [string]$resumeMetadata.LOG_FILE }
    if ($resumeMetadata.SIZES_FILE) { $SIZES_FILE = [string]$resumeMetadata.SIZES_FILE }
    if ($resumeMetadata.TRACE_ARCHIV_DIR) { $TRACE_ARCHIV_DIR = [string]$resumeMetadata.TRACE_ARCHIV_DIR }
    if ($resumeMetadata.MARKER_FILE) { $MARKER_FILE = [string]$resumeMetadata.MARKER_FILE }

    Write-Host "Resuming maintenance progress RunId=$($script:BravoProgressState.RunId)" -ForegroundColor Yellow
}

# ===== СТВОРЕННЯ НЕОБХІДНИХ ДИРЕКТОРІЙ =====
# ===== ПОЧАТОК ВИКОНАННЯ =====
$slackModeText = switch ($script:SlackMode) {
    "none" { "вимкнено" }
    "errors_only" { "лише помилки" }
    "all" { "усі повідомлення" }
    default { $script:SlackMode }
}

$exchangAPIStatus = if ($ExchangAPIServiceExists) {
    if (-not [string]::IsNullOrWhiteSpace($ExchangAPIServiceWorkingDir)) {
        "увімкнено ($ExchangAPIServiceWorkingDir)"
    }
    else {
        "увімкнено"
    }
}
else {
    "вимкнено"
}

$apacheAutoDetected = $false
$apacheExtraMessages = [System.Collections.Generic.List[string]]::new()

if ($ApacheDetectionMessages -and $ApacheDetectionMessages.Count -gt 0) {
    foreach ($apacheDetectionMessage in $ApacheDetectionMessages) {
        if ($apacheDetectionMessage -like "Каталог Br-a-vo.web визначено автоматично:*") {
            $apacheAutoDetected = $true
        }
        else {
            $apacheExtraMessages.Add($apacheDetectionMessage) | Out-Null
        }
    }
}

$apacheStatus = if ($ApacheServiceExists) {
    if ($ApacheEnabled) {
        $apacheModeText = if ($apacheAutoDetected) { ", авто" } else { "" }

        if (-not [string]::IsNullOrWhiteSpace($BRAVO_WEB_DIR)) {
            "увімкнено ($BRAVO_WEB_DIR$apacheModeText)"
        }
        else {
            "увімкнено"
        }
    }
    else {
        "вимкнено"
    }
}
else {
    "не встановлено"
}

$restoreMarkerText = if (Test-Path $MARKER_FILE) {
    "; маркер сьогодні: $([System.IO.Path]::GetFileName($MARKER_FILE))"
}
else {
    ""
}

$restoreStatus = if ($shouldRestore) {
    "АКТИВОВАНА ($restoreReason$restoreMarkerText)"
}
else {
    "ВИМКНЕНА$restoreMarkerText"
}

Write-Log -Message "==="
Write-Log -Message "=== СИСТЕМА ОБСЛУГОВУВАННЯ BRAVOSOFT ЗАПУЩЕНА | $($global:ObjectName) ==="
Write-Log -Message "==="
Write-Log -Message "Корінь: $ROOT_LIMS | Дата/час: $($currentDate.ToString('yyyy-MM-dd HH:mm:ss')) | Slack: $slackModeText" -NoTimestamp
Write-Log -Message "Служби: exchangAPI=$exchangAPIStatus | Apache=$apacheStatus" -NoTimestamp

if ($apacheExtraMessages.Count -gt 0) {
    foreach ($apacheDetectionMessage in $apacheExtraMessages) {
        Write-Log -Message "Apache: $apacheDetectionMessage" -NoTimestamp
    }
}

Write-Log -Message "Progress state file: $PROGRESS_STATE_FILE" -Level "DEBUG"

if ($script:BravoProgressStateWasResumed) {
    Write-Log -Message "Відновлення виконання після незавершеного запуску: RunId=$($script:BravoProgressState.RunId)" -Level "WARNING"
}

if ($script:EnableAutoShutdown) {
    Write-Log -Message "Автоматичне вимкнення: УВІМКНЕНО" -NoTimestamp
}

Write-Log -Message "Реставрація: $restoreStatus" -NoTimestamp
Write-Log -Message "Перевірки: розмір .md=$(if ($CheckSize) {'увімкнено'} else {'вимкнено'}) | Умови: день=$isRestoreDay, після $RestoreTime=$isAfterRestoreTime" -NoTimestamp
if ($HealthCheckOnly) {
    $healthResult = Invoke-BravoHealthCheck -SendSlack
    Close-BravoProgressState -Status $(if ($healthResult.HasCriticalIssues) {"CompletedWithErrors"} else {"Completed"})
    Send-FinalReport -LOG_FILE $LOG_FILE
    $healthExitCode = $(if ($healthResult.HasCriticalIssues) {1} else {0})
    Wait-BravoInteractiveExit -TaskUserName $TaskUserName -ExitCode $healthExitCode
    exit $healthExitCode
}
Write-Log -Message "==="
Write-Log -Message "=== ПЕРЕВІРКА ВІЛЬНОГО МІСЦЯ ==="Set-BravoProgressStep -StepId "CHECK_FREE_SPACE" -StepName "Перевірка вільного місця"
$spaceCheckResult = Check-FreeSpace -ROOT_LIMS $ROOT_LIMS

# Перевірка критичних помилок після перевірки місця
if (-not $spaceCheckResult) {
    Write-Log -Message "Критична помилка перевірки місця. Завершення скрипта." -Level "ERROR"
    exit 1
}
Complete-BravoProgressStep -StepId "CHECK_FREE_SPACE" -StepName "Перевірка вільного місця"

# ===== СТВОРЕННЯ НЕОБХІДНИХ ДИРЕКТОРІЙ =====
Set-BravoProgressStep -StepId "CREATE_DIRECTORIES" -StepName "Створення необхідних директорій"
# Перевіряємо, чи потрібно створювати будь-які директорії
$dirsToCreate = @($TRACE_DIR, $ARC_DIR, $TRACE_ARCHIV_DIR, $EXCHANGAPI_ARCHIV_DIR)
if ($ApacheServiceExists -and $ApacheEnabled) {
    $BRAVO_WEB_DAILY_DIR = "$BRAVO_WEB_ARCHIV_DIR\$YYYY-$MM-$DD"
    $dirsToCreate += $BRAVO_WEB_ARCHIV_DIR, $BRAVO_WEB_DAILY_DIR
}

# Перевіряємо, які директорії потрібно створити
$missingDirs = $dirsToCreate | Where-Object { -not (Test-Path $_) }

if ($missingDirs.Count -gt 0 -or $global:criticalErrorOccurred) {
    Write-Log -Message "==="
    Write-Log -Message "=== СТВОРЕННЯ НЕОБХІДНИХ ДИРЕКТОРІЙ ==="

    $createdDirs = [System.Collections.Generic.List[string]]::new()
    foreach ($dir in $dirsToCreate) {
        if (-not (Test-Path $dir)) {
            try {
                New-Item -Path $dir -ItemType Directory -Force -ErrorAction Stop | Out-Null
                Write-Log -Message "Створено директорію: $dir" -Level "SUCCESS"
                $createdDirs.Add($dir)
            }
            catch {
                $errorMsg = "Не вдалося створити директорію $dir : $($_.Exception.Message)"
                Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
                Send-SlackAlert -Message $errorMsg -IsCritical
                $global:criticalErrorOccurred = $true
            }
        }
    }

    # Показуємо повідомлення тільки якщо були створені директорії
    if ($createdDirs.Count -gt 0) {
        Write-Log -Message "Створено $($createdDirs.Count) директорій" -Level "SUCCESS"
    }
}

Complete-BravoProgressStep -StepId "CREATE_DIRECTORIES" -StepName "Створення необхідних директорій"
# ===== ЗУПИНКА СЛУЖБ =====
Write-Log -Message "==="
Write-Log -Message "=== ЗУПИНКА СЛУЖБ ==="Set-BravoProgressStep -StepId "STOP_SERVICES" -StepName "Зупинка служб"

# 1. Зупинка Apache
if ($ApacheServiceExists -and $ApacheEnabled) {
    try {
        $apacheProcess = Get-Process "httpd" -ErrorAction SilentlyContinue
        if ($apacheProcess) {
            Write-Log -Message "Зупинка служби Apache..." -Level "INFO"
            Start-Process $Apache -ArgumentList "-k stop" -Wait
            Start-Sleep -Seconds 3
            
            if (Get-Process "httpd" -ErrorAction SilentlyContinue) {
                Write-Log -Message "Примусове завершення Apache..." -Level "INFO"
                Stop-Process -Name "httpd" -Force
                Start-Sleep -Seconds 2
            }
            
            if (-not (Get-Process "httpd" -ErrorAction SilentlyContinue)) {
                Write-Log -Message "Apache успішно зупинено" -Level "SUCCESS"
            } else {
                $errorMsg = "Не вдалося зупинити Apache"
                Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
                Send-SlackAlert -Message $errorMsg -IsCritical
                $global:criticalErrorOccurred = $true
            }
        }
        else {
            Write-Log -Message "Apache вже зупинений - операція не потрібна" -Level "INFO"
        }
    } catch {
        $errorMsg = "Помилка при зупинці Apache: $($_.Exception.Message)"
        Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
        Send-SlackAlert -Message $errorMsg -IsCritical
        $global:criticalErrorOccurred = $true
    }
}

# 2. Зупинка exchangAPI
$exchangAPIService = Get-Service -Name $ExchangAPIServiceName -ErrorAction SilentlyContinue
if ($exchangAPIService) {
    $serviceStatus = $exchangAPIService.Status
    if ($serviceStatus -eq 'Running') {
        Write-Log -Message "Зупинка служби $ExchangAPIServiceName..." -Level "INFO"
        Stop-Service -Name $ExchangAPIServiceName -Force -WarningAction SilentlyContinue
        
        $waitTime = 30
        $startTime = Get-Date
        while ((Get-Service -Name $ExchangAPIServiceName).Status -ne 'Stopped' -and (Get-Date).Subtract($startTime).TotalSeconds -lt $waitTime) {
            Start-Sleep -Seconds 2
        }
        
        if ((Get-Service -Name $ExchangAPIServiceName).Status -eq 'Stopped') {
            Write-Log -Message "Служба $ExchangAPIServiceName успішно зупинена" -Level "SUCCESS"
        } else {
            $errorMsg = "Не вдалося зупинити службу $ExchangAPIServiceName"
            Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
            Send-SlackAlert -Message $errorMsg -IsCritical
            $global:criticalErrorOccurred = $true
        }
    } else {
        Write-Log -Message "Служба $ExchangAPIServiceName вже зупинена" -Level "INFO"
    }
} else {
    $exchangAPIProcess = Get-Process -Name $ExchangAPIProcessName -ErrorAction SilentlyContinue
    if ($exchangAPIProcess) {
        Write-Log -Message "Зупинка процесу $ExchangAPIProcessName..." -Level "INFO"
        $exchangAPIProcess | Stop-Process -Force
        Start-Sleep -Seconds 2
        
        if (-not (Get-Process -Name $ExchangAPIProcessName -ErrorAction SilentlyContinue)) {
            Write-Log -Message "Процес $ExchangAPIProcessName успішно зупинено" -Level "SUCCESS"
        } else {
            $errorMsg = "Не вдалося зупинити процес $ExchangAPIProcessName"
            Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
            Send-SlackAlert -Message $errorMsg -IsCritical
            $global:criticalErrorOccurred = $true
        }
    } else {
        Write-Log -Message "Процес $ExchangAPIProcessName не знайдено (не запущений)" -Level "INFO"
    }
}

# 3. Зупинка служби BRAVO
try {
    $bravoService = Get-CimInstance Win32_Service -Filter "Name LIKE '%$BravoServiceName%'" | 
        Select-Object -First 1
    
    if ($bravoService) {
        $BravoServiceName = $bravoService.Name
        $serviceStatus = (Get-Service -Name $BravoServiceName).Status
        
        if ($serviceStatus -eq 'Running') {
            Write-Log -Message "Зупинка служби $BravoServiceName..." -Level "INFO"
            
            # Завершення додаткових процесів
            $processNames = @("Bis")
            foreach ($procName in $processNames) {
                $process = Get-Process -Name $procName -ErrorAction SilentlyContinue
                if ($process) {
                    Write-Log -Message "Завершення процесу $procName..." -Level "INFO"
                    $process | Stop-Process -Force
                    Start-Sleep -Seconds 1
                }
            }
            
            Stop-Service -Name $BravoServiceName -Force -WarningAction SilentlyContinue
            
            $timeout = 30
            $serviceStatus = (Get-Service -Name $BravoServiceName).Status
            
            while ($serviceStatus -ne 'Stopped' -and $timeout -gt 0) {
                Start-Sleep -Seconds 1
                $timeout--
                $serviceStatus = (Get-Service -Name $BravoServiceName).Status
            }
            
            if ($serviceStatus -eq 'Stopped') {
                Write-Log -Message "Служба $BravoServiceName успішно зупинена" -Level "SUCCESS"
            } else {
                $errorMsg = "$BravoServiceName не зупинився автоматично"
                Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
                Send-SlackAlert -Message $errorMsg -IsCritical
                $global:criticalErrorOccurred = $true
            }
        }
        else {
            Write-Log -Message "Служба $BravoServiceName вже зупинена" -Level "INFO"
        }
    } else {
        $errorMsg = "СЕРВІС BRAVO НЕ ЗНАЙДЕНО! Перевірте налаштування"
        Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
        Send-SlackAlert -Message $errorMsg -IsCritical
        $global:criticalErrorOccurred = $true
    }
} catch {
    $errorMsg = "Помилка при зупинці ${BravoServiceName}: $($_.Exception.Message)"
    Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
    Send-SlackAlert -Message $errorMsg -IsCritical
    $global:criticalErrorOccurred = $true
}

Complete-BravoProgressStep -StepId "STOP_SERVICES" -StepName "Зупинка служб"
# ===== ПЕРЕВІРКА РОЗМІРІВ ФАЙЛІВ .md =====
Set-BravoProgressStep -StepId "CHECK_MD_FILE_SIZES" -StepName "Перевірка розмірів .md файлів"
Check-MdFileSizes `
    -MODEL_PATH $MODEL_PATH `
    -MAX_MD_FILE_SIZE $MAX_MD_FILE_SIZE `
    -ExcludedFiles $ExcludedMdSizeCheckFiles
Complete-BravoProgressStep -StepId "CHECK_MD_FILE_SIZES" -StepName "Перевірка розмірів .md файлів"

# ===== ОПЕРАЦІЇ ПІСЛЯ ЗУПИНКИ СЕРВІСІВ =====
$bravoStatus = if ($bravoService) { (Get-Service -Name $BravoServiceName).Status } else { 'Unknown' }
if ($bravoStatus -ne "Running") {
    if ($shouldRestore) {
        try {
            Write-Log -Message "==="
            Write-Log -Message "=== РЕСТАВРАЦІЯ МОДЕЛІ ==="
            Set-BravoProgressStep -StepId "RESTORE_MODEL" -StepName "Реставрація моделі"
            
            if ($CheckSize) {
                Write-Log -Message "До реставрації: збереження розмірів файлів..." -Level "DEBUG"
                $initialSizes = Get-ChildItem -Path $MODEL_PATH -Recurse -File | 
                    ForEach-Object {
                        [PSCustomObject]@{
                            RelativePath = $_.FullName.Replace($MODEL_PATH, "").TrimStart('\')
                            SizeBytes = $_.Length
                        }
                    }
                
                # Запис без BOM
                $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                $csvData = $initialSizes | ConvertTo-Csv -NoTypeInformation
                [System.IO.File]::WriteAllLines($SIZES_FILE, $csvData, $utf8NoBom)
                
                Write-Log -Message "До реставрації: розміри збережено -> $SIZES_FILE" -Level "SUCCESS"
            }
            
            # Архівація перед реставрацією
            $archivePathBefore = "$ARC_DIR\$ARCH_NAME1"
            $archiveCreatedBefore = $false

            if ((Test-Path -LiteralPath $archivePathBefore) -or (Test-Path -LiteralPath "$archivePathBefore.sha512")) {
                $beforeShaResult = Test-BravoArchiveSha512 -ArchivePath $archivePathBefore

                if ($beforeShaResult.Status -eq "Valid") {
                    Write-Log -Message "Before-архів уже існує і SHA512 валідний. Повторне створення пропущено: $archivePathBefore" -Level "WARNING"
                    $archiveCreatedBefore = $true
                }
                else {
                    $errorMsg = "Before-архів уже існує, але SHA512 невалідний або відсутній. Реставрацію зупинено, щоб не перезаписати аварійний backup: $archivePathBefore"
                    Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
                    Send-SlackAlert -Message $errorMsg -IsCritical
                    $global:criticalErrorOccurred = $true
                    $archiveCreatedBefore = $false
                }
            }
            else {
                $archiveCreatedBefore = New-BravoVerifiedArchive `
                    -ArchivePath $archivePathBefore `
                    -SourcePath "$MODEL_PATH\*" `
                    -ArcCommonParams $arcCommonParams `
                    -ARC_PATH $ARC_PATH `
                    -Description "Архівація моделі перед реставрацією"
            }

            $exitCode = if ($archiveCreatedBefore) { 0 } else { 1 }
            
            if ($exitCode -ne 0) {
                $errorMsg = "Архівація моделі перед реставрацією не вдалася! Код помилки: $exitCode. Реставрація скасована."
                Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
                Send-SlackAlert -Message $errorMsg -IsCritical
                $global:criticalErrorOccurred = $true
            } else {
                
                # Перевірка контрольних сум після архівації (лише для before)
                $null = Verify-Backup -ArchivePath "$ARC_DIR\$ARCH_NAME1"
                Write-Log -Message "Архів до реставрації: створено, перевірено 7-Zip, SHA512 збережено -> $ARC_DIR\$ARCH_NAME1" -Level "SUCCESS"
                
                # Виконання реставрації через bravocmd.exe (як в еталоні)
                $restoreArgs = @("r", "null", "$ROOT_LIMS\MODEL\lims")
                $exitCode = Invoke-CommandWithLog -Command "$ROOT_LIMS\bravocmd.exe" -Arguments $restoreArgs -Description "Виконання реставрації моделі LIMS"
                
                if ($exitCode -eq 0) {
                    Write-Log -Message "Реставрація LIMS: успішно завершена" -Level "SUCCESS"
                    
                    # Архівація після реставрації ВИКОНУЄТЬСЯ З УМОВАМИ
                    $restoreRequired = $false
                    $createMarker = $true
                    
                    if ($CheckSize) {
                        Write-Log -Message "Перевірка змін: порівняння розмірів файлів..." -Level "DEBUG"
                        $criticalChanges = Compare-FileSizes -BeforeFile $SIZES_FILE -ModelPath $MODEL_PATH -MinSizeBytes 2048
                        
                        if ($criticalChanges) {
                            Write-Log -Message "УВАГА: Виявлено критичні зміни розмірів файлів!" -Level "WARNING"
                        }
                        else {
                            Write-Log -Message "Перевірка змін: розміри файлів без змін" -Level "SUCCESS"
                        }

                        if ($criticalChanges) {
                            Write-Log -Message "Відновлення моделі з архіву перед реставрацією..." -Level "INFO"
                            
                            $exitCode = Restore-FromArchive -ArchivePath "$ARC_DIR\$ARCH_NAME1" -Destination $MODEL_PATH -ARC_PATH $ARC_PATH
                            if ($exitCode -eq 0) {
                                Write-Log -Message "Модель успішно відновлена з архіву перед реставрації" -Level "SUCCESS"
                                $restoreRequired = $true
                                $createMarker = $false  # Скасувати маркер
                            }
                        }
                    }
                    
                    # Виконуємо архівацію після реставрації ЛИШЕ якщо не було критичних змін
                    if (-not $restoreRequired) {
                        $archivePathAfter = "$ARC_DIR\$ARCH_NAME2"
                        $archiveCreatedAfter = New-BravoVerifiedArchive `
                            -ArchivePath $archivePathAfter `
                            -SourcePath "$MODEL_PATH\*" `
                            -ArcCommonParams $arcCommonParams `
                            -ARC_PATH $ARC_PATH `
                            -Description "Архівація моделі після реставрації"
                        $exitCode = if ($archiveCreatedAfter) { 0 } else { 1 }
                        if ($exitCode -eq 0) {
                            $null = Verify-Backup -ArchivePath "$ARC_DIR\$ARCH_NAME2"
                            Write-Log -Message "Архів після реставрації: створено, перевірено 7-Zip, SHA512 збережено -> $ARC_DIR\$ARCH_NAME2" -Level "SUCCESS"
                        }
                        
                        # Створення маркера ЛИШЕ при успішній реставрації без критичних змін
                        if ($createMarker -and -not $ForceRestore) {
                            Set-Content -Path $MARKER_FILE -Value "Реставрація виконана $NOW"
                            Write-Log -Message "Маркер реставрації: створено -> $MARKER_FILE" -Level "SUCCESS"
                        }

                        Write-Log -Message "Статус реставрації: УСПІШНО" -Level "SUCCESS"
                    } else {
                        Write-Log -Message "Архівація після реставрації ПРОПУЩЕНА через критичні зміни" -Level "WARNING"
                    }
                }
            }
        }
        catch {
            $errorMsg = "Критична помилка під час реставрації: $($_.Exception.Message)"
            Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
            Send-SlackAlert -Message $errorMsg -IsCritical
            $global:criticalErrorOccurred = $true
        }
        if (-not $global:criticalErrorOccurred) {
            Complete-BravoProgressStep -StepId "RESTORE_MODEL" -StepName "Реставрація моделі"
        }
    }
    
    # Обробка лог-файлів (об'єднаний етап)
    Set-BravoProgressStep -StepId "PROCESS_LOG_FILES" -StepName "Обробка лог-файлів"
    try {
        Write-Log -Message "==="
        # Обробка trace-файлів
        Write-Log -Message "=== ОБРОБКА TRACE-ФАЙЛІВ ===" -Level "INFO"
        $outFiles = Get-ChildItem -Path "$ROOT_LIMS" -Filter "*.out" -ErrorAction SilentlyContinue
        if ($outFiles) {
            foreach ($file in $outFiles) {
                $null = Move-WithSequence -sourcePath $file.FullName -destDir $TRACE_ARCHIV_DIR -SkipIfEmpty
            }
            Write-Log -Message "Оброблено $($outFiles.Count) trace-файлів" -Level "SUCCESS"
        } else {
            Write-Log -Message "[ІНФО] Немає trace-файлів для обробки" -Level "INFO"
        }
        
        # Обробка логів exchangAPI
        Write-Log "==="
        Write-Log -Message "=== ОБРОБКА ЛОГІВ EXCHANGAPI ===" -Level "INFO"
        $exchangAPILogs = Get-ChildItem -Path "$ROOT_LIMS" -Filter "exchangAPI_*.log" -ErrorAction SilentlyContinue
        if ($exchangAPILogs) {
            foreach ($file in $exchangAPILogs) {
                $null = Move-ExchangAPILogs -sourcePath $file.FullName -destDir $EXCHANGAPI_ARCHIV_DIR
            }
        Write-Log -Message "Оброблено $($exchangAPILogs.Count) лог-файлів exchangAPI" -Level "SUCCESS"
            } else {
        Write-Log -Message "[ІНФО] Немає лог-файлів exchangAPI для обробки" -Level "INFO"
        }
		
        # Обробка логів Apache
        if ($ApacheServiceExists -and $ApacheEnabled) {
            Write-Log -Message "=== ОБРОБКА ЛОГІВ APACHE ===" -Level "INFO"
            $apacheLogFiles = Get-ChildItem -Path $APACHE_LOGS_DIR -File -ErrorAction SilentlyContinue | 
                Where-Object { $_.Length -gt 0 }
            
            if ($apacheLogFiles) {
                foreach ($file in $apacheLogFiles) {
                    $null = Move-WithSequence -sourcePath $file.FullName -destDir $BRAVO_WEB_DAILY_DIR -SkipIfEmpty
                }
                Write-Log -Message "Оброблено $($apacheLogFiles.Count) Apache файлів" -Level "SUCCESS"
            } else {
                Write-Log -Message "[ІНФО] Немає Apache файлів для обробки" -Level "INFO"
            }
        }
        
        # Обробка логів WWW
        if ($ApacheServiceExists -and $ApacheEnabled) {
            Write-Log -Message "=== ОБРОБКА ЛОГІВ WWW ===" -Level "INFO"
            $wwwLogFiles = Get-ChildItem -Path $WWW_LOGS_DIR -File -ErrorAction SilentlyContinue | 
                Where-Object { $_.Length -gt 0 }
            
            if ($wwwLogFiles) {
                foreach ($file in $wwwLogFiles) {
                    $null = Move-WithSequence -sourcePath $file.FullName -destDir $BRAVO_WEB_DAILY_DIR -SkipIfEmpty
                }
                Write-Log -Message "Оброблено $($wwwLogFiles.Count) WWW файлів" -Level "SUCCESS"
            } else {
                Write-Log -Message "[ІНФО] Немає WWW файлів для обробки" -Level "INFO"
            }
        }
    }
    catch {
        $errorMsg = "Помилка при обробці лог-файлів: $($_.Exception.Message)"
        Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
        Send-SlackAlert -Message $errorMsg
        $global:criticalErrorOccurred = $true
    }

    if (-not $global:criticalErrorOccurred) {
        Complete-BravoProgressStep -StepId "PROCESS_LOG_FILES" -StepName "Обробка лог-файлів"
    }
}
else {
    $errorMsg = "Сервіс $($BravoServiceName) все ще працює. Операції з файлами пропущено."
    Write-Log -Message $errorMsg -Level "ERROR"
    Send-SlackAlert -Message $errorMsg
    $global:criticalErrorOccurred = $true
}

# ===== ЗАПУСК СЕРВІСІВ =====
Write-Log -Message "==="
Write-Log -Message "=== ЗАПУСК СЛУЖБ ==="Set-BravoProgressStep -StepId "START_SERVICES" -StepName "Запуск служб"

# 1. Запуск служби BRAVO
try {
    if ($bravoService -and (Get-Service -Name $BravoServiceName).Status -ne 'Running') {
        Write-Log -Message "Запуск служби $BravoServiceName..." -Level "INFO"
        Start-Service -Name $BravoServiceName -WarningAction SilentlyContinue
        
        $timeout = 60
        $serviceStatus = (Get-Service -Name $BravoServiceName).Status
        
        while ($serviceStatus -ne 'Running' -and $timeout -gt 0) {
            Start-Sleep -Seconds 5
            $timeout -= 5
            $serviceStatus = (Get-Service -Name $BravoServiceName).Status
        }
        
        if ($serviceStatus -eq 'Running') {
            Write-Log -Message "Служба $BravoServiceName успішно запущена" -Level "SUCCESS"
        } else {
            $errorMsg = "$BravoServiceName не запустився автоматично"
            Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
            Send-SlackAlert -Message $errorMsg -IsCritical
            $global:criticalErrorOccurred = $true
        }
    }
} catch {
    $errorMsg = "Помилка при запуску ${BravoServiceName}: $($_.Exception.Message)"
    Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
    Send-SlackAlert -Message $errorMsg -IsCritical
    $global:criticalErrorOccurred = $true
}

# 2. Запуск exchangAPI
if ($exchangAPIService) {
    $serviceStatus = (Get-Service -Name $ExchangAPIServiceName).Status
    if ($serviceStatus -ne 'Running') {
        Write-Log -Message "Запуск служби $ExchangAPIServiceName..." -Level "INFO"
        Start-Service -Name $ExchangAPIServiceName -WarningAction SilentlyContinue
        
        $waitTime = 30
        $startTime = Get-Date
        while ((Get-Service -Name $ExchangAPIServiceName).Status -ne 'Running' -and (Get-Date).Subtract($startTime).TotalSeconds -lt $waitTime) {
            Start-Sleep -Seconds 2
        }
        
        if ((Get-Service -Name $ExchangAPIServiceName).Status -eq 'Running') {
            Write-Log -Message "Служба $ExchangAPIServiceName успішно запущена" -Level "SUCCESS"
        } else {
            $errorMsg = "$ExchangAPIServiceName не запустився автоматично"
            Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
            Send-SlackAlert -Message $errorMsg -IsCritical
            $global:criticalErrorOccurred = $true
        }
    } else {
        Write-Log -Message "Служба $ExchangAPIServiceName вже запущена" -Level "INFO"
    }
} else {
    if (Test-Path $ExchangAPIExePath) {
        Write-Log -Message "Запуск процесу $ExchangAPIProcessName..." -Level "INFO"
        Start-Process -FilePath $ExchangAPIExePath -WindowStyle Hidden
        
        Start-Sleep -Seconds 3
        if (Get-Process -Name $ExchangAPIProcessName -ErrorAction SilentlyContinue) {
            Write-Log -Message "Процес $ExchangAPIProcessName успішно запущено" -Level "SUCCESS"
        } else {
            $errorMsg = "Не вдалося запустити процес $ExchangAPIProcessName"
            Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
            Send-SlackAlert -Message $errorMsg -IsCritical
            $global:criticalErrorOccurred = $true
        }
    } else {
        $errorMsg = "Файл $ExchangAPIExePath не знайдено"
        Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
        Send-SlackAlert -Message $errorMsg
    }
}

# 3. Запуск Apache (виконується останнім)
if ($ApacheServiceExists -and $ApacheEnabled) {
    try {
        if (-not (Get-Process "httpd" -ErrorAction SilentlyContinue)) {
            Write-Log -Message "Запуск служби Apache..." -Level "INFO"
            Start-Process $Apache -ArgumentList "-D SSL -k start" -Wait
            Start-Sleep -Seconds 3
            
            if (-not (Get-Process "httpd" -ErrorAction SilentlyContinue)) {
                Write-Log -Message "Спроба альтернативного запуску Apache..." -Level "INFO"
                Start-Process $Apache -ArgumentList "-k start" -Wait
                Start-Sleep -Seconds 3
            }
            
            if (Get-Process "httpd" -ErrorAction SilentlyContinue) {
                Write-Log -Message "Служба Apache успішно запущена" -Level "SUCCESS"
            } else {
                $errorMsg = "Apache не запустився"
                Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
                Send-SlackAlert -Message $errorMsg -IsCritical
                $global:criticalErrorOccurred = $true
            }
        }
    } catch {
        $errorMsg = "Помилка при запуску Apache: $($_.Exception.Message)"
        Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
        Send-SlackAlert -Message $errorMsg -IsCritical
        $global:criticalErrorOccurred = $true
    }
}

Complete-BravoProgressStep -StepId "START_SERVICES" -StepName "Запуск служб"
# ===== ОЧИСТКА СТАРИХ ДАНИХ =====Set-BravoProgressStep -StepId "CLEANUP_OLD_DATA" -StepName "Очистка старих даних"
# Перевіряємо, чи є що очищати
$hasDataToClean = $false

# Перевірка Trace
$traceOldDirs = Get-ChildItem -Path $TRACE_DIR -Directory -ErrorAction SilentlyContinue | 
    Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and $_.CreationTime -lt (Get-Date).AddDays(-$ARCHIVE_RETENTION_DAYS) }
$traceOldLogs = Get-ChildItem -Path $LOG_DIR -File -ErrorAction SilentlyContinue | 
    Where-Object { 
        $_.CreationTime -lt (Get-Date).AddDays(-$LOG_RETENTION_DAYS) -and 
        ($_.Name -like "script_log_*.txt" -or 
         $_.Name -like "file_sizes_*.csv" -or 
         $_.Name -like "restore_done_*.marker")
    }

# Перевірка архівів реставрації
$mainArchivePatterns = @("${ArchivePrefix}_before_*.mdz", "${ArchivePrefix}_after_*.mdz")
$mainArchiveFiles = $mainArchivePatterns | ForEach-Object {
    Get-ChildItem -Path $ARC_DIR -Filter $_ -ErrorAction SilentlyContinue
}

if ($mainArchiveFiles -and $mainArchiveFiles.Count -gt 0) {
    $archiveGroups = $mainArchiveFiles | Group-Object { 
        if ($_.Name -match "${ArchivePrefix}_(before|after)_(\d{8}_\d{4})\.mdz") {
            $Matches[2]
        } else {
            $_.CreationTime.ToString("yyyyMMdd_HHmm")
        }
    }
    $sortedGroups = $archiveGroups | Sort-Object Name -Descending
    $groupsToDelete = $sortedGroups | Select-Object -Skip $RESTORE_ARCHIVES_KEEP_COUNT
    $hasDataToClean = $hasDataToClean -or ($groupsToDelete.Count -gt 0)
} else {
    $groupsToDelete = @()
}

# Перевірка логів exchangAPI
$exchangAPIOldLogs = Get-ChildItem -Path $EXCHANGAPI_ARCHIV_DIR -File -ErrorAction SilentlyContinue | 
    Where-Object { 
        $_.CreationTime -lt (Get-Date).AddDays(-$LOG_RETENTION_DAYS) -and 
        $_.Name -like "exchangAPI_*.log"
    }

# Перевірка Br-a-vo.web (якщо Apache встановлений)
if ($ApacheServiceExists -and $ApacheEnabled) {
    $bravoWebOldDirs = Get-ChildItem -Path $BRAVO_WEB_ARCHIV_DIR -Directory -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and $_.CreationTime -lt (Get-Date).AddDays(-$ARCHIVE_RETENTION_DAYS) }
    $hasDataToClean = $hasDataToClean -or ($bravoWebOldDirs.Count -gt 0)
}

# Загальна перевірка наявності даних для очищення
$hasDataToClean = $hasDataToClean -or ($traceOldDirs.Count -gt 0) -or ($traceOldLogs.Count -gt 0) -or ($exchangAPIOldLogs.Count -gt 0)

# Якщо є дані для очищення - показуємо заголовок
if ($hasDataToClean) {
    Write-Log -Message "==="
    Write-Log -Message "=== ОЧИСТКА СТАРИХ ДАНИХ ==="
}

# Обробка Trace (тільки якщо є що обробляти)
if ($traceOldDirs.Count -gt 0 -or $traceOldLogs.Count -gt 0) {
    Process-OldData -Path $TRACE_DIR -ArchiveNamePrefix "Trace" -RetentionDays $ARCHIVE_RETENTION_DAYS -arcCommonParams $arcCommonParams -ARC_PATH $ARC_PATH
}

# Обробка логів Br-a-vo.web (лише якщо служба Apache встановлена і є дані)
if ($ApacheServiceExists -and $ApacheEnabled -and $bravoWebOldDirs.Count -gt 0) {
    Process-OldData -Path $BRAVO_WEB_ARCHIV_DIR -ArchiveNamePrefix "WebLogs" -RetentionDays $ARCHIVE_RETENTION_DAYS -arcCommonParams $arcCommonParams -ARC_PATH $ARC_PATH
}

# Очистка старих лог-файлів (всіх типів) - тільки якщо є що видаляти
if ($traceOldLogs.Count -gt 0) {
    Remove-OldLogFiles -Path $LOG_DIR -RetentionDays $LOG_RETENTION_DAYS
}

# Видалення старих архівів реставрації - тільки якщо є що видаляти
if ($groupsToDelete.Count -gt 0) {
    Remove-OldRestoreArchives -Path $ARC_DIR -ArchivePrefix $ArchivePrefix -KeepCount $RESTORE_ARCHIVES_KEEP_COUNT
}

# Видалення старих логів exchangAPI - тільки якщо є що видаляти
if ($exchangAPIOldLogs.Count -gt 0) {
    Remove-OldLogFiles -Path $EXCHANGAPI_ARCHIV_DIR -RetentionDays $LOG_RETENTION_DAYS
}

Complete-BravoProgressStep -StepId "CLEANUP_OLD_DATA" -StepName "Очистка старих даних"
# ===== ЗАПУСК ДОДАТКОВОГО СКРИПТУ ARCHIV_LIMS =====Set-BravoProgressStep -StepId "ARCHIV_LIMS" -StepName "Запуск додаткового скрипту ARCHIV_LIMS"
if ($script:EnableArchivLims) {
    Write-Log -Message "==="
    Write-Log -Message "=== ЗАПУСК СКРИПТУ ARCHIV_LIMS ==="

    try {
        $archivLimsPath = Join-Path -Path $PSScriptRoot -ChildPath "ARCHIV_LIMS.ps1"
        
        if (Test-Path $archivLimsPath) {
            Write-Log -Message "Запуск скрипту ARCHIV_LIMS.ps1..." -Level "INFO"
            
            # Запускаємо скрипт з такими ж параметрами
            $archivParams = @()
            if ($ForceRestore) { $archivParams += "-ForceRestore" }
            if ($DisableSizeCheck) { $archivParams += "-DisableSizeCheck" }
            if ($EnableAllSlack) { $archivParams += "-EnableAllSlack" }
            if ($DisableAllSlack) { $archivParams += "-DisableAllSlack" }
            if ($AutoShutdown -eq "on") { $archivParams += "-AutoShutdown" }
            if ($ArchivLims -eq "on") { $archivParams += "-ArchivLims" }
            
            $archivProcess = Start-Process -FilePath "powershell.exe" `
                -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$archivLimsPath`" $($archivParams -join ' ')" `
                -Wait `
                -PassThru `
                -NoNewWindow
            
            if ($archivProcess.ExitCode -eq 0) {
                Write-Log -Message "Скрипт ARCHIV_LIMS.ps1 успішно виконано" -Level "SUCCESS"
            } else {
                Write-Log -Message "Скрипт ARCHIV_LIMS.ps1 завершено з кодом помилки: $($archivProcess.ExitCode)" -Level "WARNING"
            }
        } else {
            Write-Log -Message "Скрипт ARCHIV_LIMS.ps1 не знайдено за шляхом: $archivLimsPath" -Level "WARNING"
        }
    }
    catch {
        Write-Log -Message "Помилка під час запуску скрипту ARCHIV_LIMS.ps1: $($_.Exception.Message)" -Level "ERROR"
    }
} else {
    # Мінімальне інформаційне повідомлення без заголовків
    Write-Log -Message "Запуск ARCHIV_LIMS: вимкнено" -Level "DEBUG"
}

Complete-BravoProgressStep -StepId "ARCHIV_LIMS" -StepName "Запуск додаткового скрипту ARCHIV_LIMS"
# ===== ВИКЛИК ФУНКЦІЇ АВТОМАТИЧНОГО ВИМКНЕННЯ =====
if ($script:EnableAutoShutdown) {
    Invoke-AutoShutdown -Timeout $ShutdownTimeout
} else {
    # Мінімальне інформаційне повідомлення без заголовків
    Write-Log -Message "Автоматичне вимкнення: вимкнено" -Level "DEBUG"
}

# Відправляємо фінальний звіт
Send-FinalReport -LOG_FILE $LOG_FILE

# Додаємо інформацію про статус відправки Slack
# if ($script:SlackMode -ne "none") {
    # Видаліть перевірку $slackReportSent, оскільки тепер функція нічого не повертає
#     Write-Log -Message "Фінальний звіт оброблено" -Level "INFO"
# }

# ===== ЗАВЕРШЕННЯ СКРИПТУ =====
$totalTime = (Get-Date) - $global:ScriptStartTime

# ФІНАЛЬНИЙ БЛОК ЗАВЕРШЕННЯ
Close-BravoProgressState -Status $(if ($global:criticalErrorOccurred) {"CompletedWithErrors"} else {"Completed"})
Write-Log -Message "==="
Write-Log -Message "=== СИСТЕМА ОБСЛУГОВУВАННЯ BRAVOSOFT ЗАВЕРШИЛА РОБОТУ ==="
Write-Log -Message "=== УСТАНОВА: $($global:ObjectName) ==="
Write-Log -Message "=== ЧАС ВИКОНАННЯ: $(Format-Duration $totalTime) ==="
Write-Log -Message "=== СТАТУС: $(if ($global:criticalErrorOccurred) {'З ПОМИЛКАМИ'} else {'УСПІШНО'}) ==="
Write-Log -Message "==="

$exitCode = $(if ($global:criticalErrorOccurred) {1} else {0})
Wait-BravoInteractiveExit -TaskUserName $TaskUserName -ExitCode $exitCode
exit $exitCode








