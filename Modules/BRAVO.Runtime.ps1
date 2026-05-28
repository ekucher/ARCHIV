# ==============================================================================
# BRAVO.Runtime.ps1
# Спільні runtime-функції для консольних скриптів BRAVO.
# ==============================================================================

function Wait-BeforeClose {
    if ($global:BravoScheduledTaskRun) { return }
    $isInteractive = [Environment]::UserInteractive
    $isPowerShellISE = $Host.Name -like "*ISE*"
    $isConsole = $Host.Name -like "*ConsoleHost*"

    if ($isInteractive -and $isConsole -and -not $isPowerShellISE) {
        Write-Host ""
        Write-Host "Натисніть Enter для закриття..." -ForegroundColor Yellow
        Read-Host
    }
}

function Write-UacRestartLog {
    param(
        [string[]]$Lines,
        [string]$LogFileName
    )

    try {
        if ([string]::IsNullOrWhiteSpace($LogFileName)) {
            if ($global:BravoUacRestartLogName) {
                $LogFileName = $global:BravoUacRestartLogName
            } else {
                $LogFileName = "UAC_RESTART.log"
            }
        }

        $rootPath = if ($global:BravoScriptRoot) { $global:BravoScriptRoot } else { Split-Path $PSScriptRoot -Parent }
        $uacLogDir = Join-Path $rootPath "LOGS"
        if (-not (Test-Path -LiteralPath $uacLogDir)) {
            New-Item -ItemType Directory -Path $uacLogDir -Force | Out-Null
        }

        $uacLog = Join-Path $uacLogDir $LogFileName
        $Lines | Out-File -LiteralPath $uacLog -Encoding UTF8 -Append
        return $uacLog
    } catch {
        return $null
    }
}


function Write-BravoLogFileLine {
    param(
        [string]$Line,
        [string]$Path = $global:LOG_FILE
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return }

    try {
        $dir = Split-Path -Path $Path -Parent
        if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $Line | Out-File -FilePath $Path -Append -Encoding UTF8
    } catch {
        Write-Host "Помилка запису у файл логу: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Assert-BravoAdministrator {
    param([string]$ScriptName = "BRAVO")

    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "ПОМИЛКА: Для виконання $ScriptName потрібні права адміністратора." -ForegroundColor Red
        Write-Host "Запустіть PowerShell від імені адміністратора або використайте ручний запуск через BRAVO.ps1." -ForegroundColor Yellow
        Wait-BeforeClose
        exit 1
    }
}

function Assert-BravoPowerShellVersion {
    param(
        [int]$Major = 5,
        [int]$Minor = 1
    )

    if ($PSVersionTable.PSVersion.Major -lt $Major -or ($PSVersionTable.PSVersion.Major -eq $Major -and $PSVersionTable.PSVersion.Minor -lt $Minor)) {
        Write-Host "ПОМИЛКА: Необхідна версія PowerShell $Major.$Minor або вище" -ForegroundColor Red
        exit 1
    }
}

function Assert-Bravo64BitOperatingSystem {
    if (-not [Environment]::Is64BitOperatingSystem) {
        Write-Host "ПОМИЛКА: Скрипт працює тільки на 64-бітних системах" -ForegroundColor Red
        exit 1
    }
}

function Assert-BravoWindowsVersion {
    $osVersion = [System.Environment]::OSVersion.Version
    if ($osVersion.Major -lt 6 -or ($osVersion.Major -eq 6 -and $osVersion.Minor -lt 3)) {
        Write-Host "ПОМИЛКА: Скрипт вимагає Windows 8.1/Windows Server 2012 R2 або новішої версії" -ForegroundColor Red
        exit 1
    }
}

function Assert-BravoArchivFolder {
    param([string]$ScriptPath)

    if ((Split-Path -Leaf $ScriptPath) -ne "ARCHIV") {
        $errorMessage = "ПОМИЛКА: Скрипт має запускатись лише з папки ARCHIV!"
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $errorMessage" | Out-File "$env:TEMP\lims_error.log" -Append
        Write-Host $errorMessage -ForegroundColor Red
        exit 1
    }
}

function Initialize-BravoDirectory {
    param(
        [string]$Path,
        [string]$Description = "каталог"
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        try {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
        } catch {
            Write-Host "Не вдалося створити $Description $Path : $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
    }
}