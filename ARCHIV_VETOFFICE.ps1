##########
# BravoSoft
# Author: Evgeniy Kucher
# Version: 2.1, 2025-12-11
# Скрипт для архівації та резервного копіювання даних VETOFFICE системи
# Модифікована версія з покращеним логуванням
# Конфігурація винесена в окремий файл
##########

# Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass –Force

# Запит на підвищення дозволу виконання скрипта
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (!$currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Потрiбнi права адмiнiстратора. Запит UAC..." -ForegroundColor Yellow
    
    # Створюємо процес з явним запитом UAC
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = "powershell.exe"
    $processInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $processInfo.Verb = "runas"  # Це викликає UAC
    $processInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Normal
    
    try {
    $process = [System.Diagnostics.Process]::Start($processInfo)
    Exit  # Коректне завершення батьківського процесу
} catch {
    Write-Host "UAC запит вiдхилено або сталася помилка: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Запустiть PowerShell з правами адмiнiстратора вручну" -ForegroundColor Yellow
    Exit 1
    }
}

# =============================================
# ЗАВАНТАЖЕННЯ КОНФІГУРАЦІЇ
# =============================================

# Змінні версії
$ScriptVersion = "2.1"
$ScriptDate = "2025-12-11"

# Шлях до файлу конфігурації
$configPath = Join-Path $PSScriptRoot "ARCHIV_VETOFFICE.config.ps1"

# Перевірка наявності файлу конфігурації
if (-not (Test-Path $configPath)) {
    Write-Host "ПОМИЛКА: Файл конфiгурацiї не знайдено: $configPath" -ForegroundColor Red
    Write-Host "Створiть файл ARCHIV_VETOFFICE.config.ps1 на основi шаблону." -ForegroundColor Yellow
    Exit 1
}

# Завантаження конфігурації
try {
    # Видаляємо глобальні змінні перед завантаженням нових
    Get-Variable | Where-Object { $_.Name -like "global:*" -and $_.Name -notlike "global:?*" } | Remove-Variable -ErrorAction SilentlyContinue
    
    # Завантажуємо конфігурацію
    . $configPath
    
    Write-Host "Конфiгурацiю завантажено успiшно: $configPath" -ForegroundColor Green
} catch {
    Write-Host "ПОМИЛКА: Не вдалося завантажити конфiгурацiю: $($_.Exception.Message)" -ForegroundColor Red
    Exit 1
}

# =============================================
# ІНІЦІАЛІЗАЦІЯ ЗМІННИХ З КОНФІГУРАЦІЇ
# =============================================

# РЕЖИМ СУМІСНОСТІ
$compatibilityMode = $false  # Автоматично визначається нижче

# ШЛЯХИ ДО ІНСТРУМЕНТІВ
$arcPath = Join-Path $toolsPath "7za.exe"
$winSCPPath = Join-Path $toolsPath "WinSCP.com"

# КОНФІГУРАЦІЙНИЙ ОБ'ЄКТ (для сумісності з існуючим кодом)
$config = @{
    RootPath = $rootPath
    ArchivPath = $archivPath
    ToolsPath = $toolsPath
    LogPath = $logPath
    ArchivePrefix = $archivePrefix
    LogRetentionDays = $logRetentionDays
    ArchiveVersions = $archiveVersions
    EnableArchiveDeletion = $enableArchiveDeletion
    EnableSFTPUpload = $enableSFTPUpload
    EnableNetworkCopy = $enableNetworkCopy  # НОВИЙ параметр
    CompatibilityMode = $compatibilityMode
    ExcludeComponents = $excludeComponents
    ShowSystemInfo = $showSystemInfo
    ShowHardwareInfo = $showHardwareInfo
    ShowPerformanceInfo = $showPerformanceInfo
}

# ІНСТРУМЕНТИ (для сумісності з існуючим кодом)
$tools = @{
    ArcPath = $arcPath
    WinSCPPath = $winSCPPath
}

# SFTP КОНФІГ (для сумісності з існуючим кодом)
$sftpConfig = @{
    Login = $Login
    Password = $Password
    Url = $sftpUrl
    HostKey = $sftpHostKey
    Directories = $sftpDirectories
}

# МЕРЕЖЕВА КОНФІГ (для сумісності з існуючим кодом)
$networkCopyConfig = @{
    Enabled = $enableNetworkCopy
    NetworkPath = $networkCopyConfig.NetworkPath
    Username = $networkCopyConfig.Username
    Password = $networkCopyConfig.Password
    MaxRetries = $networkCopyConfig.MaxRetries
    RetryDelay = $networkCopyConfig.RetryDelay
}

# =============================================
# НАЛАШТУВАННЯ КОНСОЛІ
# =============================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "СКРИПТ АРХIВАЦIЇ VETOFFICE v.$ScriptVersion (МОДИФІКОВАНИЙ)"
$Host.UI.RawUI.BackgroundColor = "Black"
$Host.UI.RawUI.ForegroundColor = "White"
Clear-Host

# =============================================
# ФУНКЦІЯ ДЛЯ РОБОТИ З ПЛАНУВАЛЬНИКОМ
# =============================================

function Add-ToTaskScheduler {
    param(
        [string]$TaskName = "ARCHIV_VETOFFICE_Backup",  # Назва завдання в Планувальнику
        [string]$ScriptPath = $PSCommandPath,           # Шлях до скрипта PowerShell
        [string]$StartTime = "02:00",                   # Час запуску завдання (формат HH:MM)
        [int]$IntervalDays = 1                          # Інтервал днів між запусками
    )
    
    Write-Host "`n=== НАЛАШТУВАННЯ ПЛАНУВАЛЬНИКА ЗАВДАНЬ ===" -ForegroundColor Yellow
    
    # Запит часу запуску
    Write-Host "`nУ який час запускати архiвацiю?" -ForegroundColor Cyan
    Write-Host "Формат: HH:MM (наприклад, 02:00, 23:30)" -ForegroundColor Gray
    $userTime = Read-Host "Час запуску (за замовчуванням $StartTime)"
    
    if ([string]::IsNullOrWhiteSpace($userTime)) {
        $userTime = $StartTime
    }
    
    # Валідація формату часу
    if ($userTime -notmatch '^([01]?[0-9]|2[0-3]):([0-5][0-9])$') {
        Write-Host "Невiрний формат часу! Використовується значення за замовчуванням: $StartTime" -ForegroundColor Red
        $userTime = $StartTime
    }
    
    # Розбиваємо час на години та хвилини
    $timeParts = $userTime -split ':'
    $hour = [int]$timeParts[0]
    $minute = [int]$timeParts[1]
    
    # Запит інтервалу
    Write-Host "`nЯк часто виконувати архiвацiю?" -ForegroundColor Cyan
    Write-Host "1. Щодня" -ForegroundColor Gray
    Write-Host "2. Щотижня" -ForegroundColor Gray
    Write-Host "3. Щомiсяця" -ForegroundColor Gray
    $intervalChoice = Read-Host "Оберiть варiант (1-3, за замовчуванням 1)"
    
    switch ($intervalChoice) {
        "2" { 
            $interval = "Weekly"
            $daysOfWeek = "Monday, Tuesday, Wednesday, Thursday, Friday"
            Write-Host "Завдання буде виконуватися щотижня у буднi" -ForegroundColor Green
        }
        "3" { 
            $interval = "Monthly"
            Write-Host "Завдання буде виконуватися щомiсяця 1-го числа" -ForegroundColor Green
        }
        default { 
            $interval = "Daily"
            Write-Host "Завдання буде виконуватися щодня" -ForegroundColor Green
        }
    }
    
    # Створюємо безпечне ім'я завдання (замінюємо двокрапку на підкреслення)
    $safeTime = $userTime -replace ':', '_'
    $taskName = "${TaskName}_${safeTime}"
    
    Write-Host "`nСтворення завдання в Планувальнику..." -ForegroundColor Yellow
    Write-Host "Назва завдання: $taskName" -ForegroundColor White
    Write-Host "Час запуску: $userTime" -ForegroundColor White
    Write-Host "Шлях до скрипта: $ScriptPath" -ForegroundColor White
    
    # Перевіряємо, чи існує вже таке завдання
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    
    if ($existingTask) {
        Write-Host "Завдання вже iснує! Видаляємо старе..." -ForegroundColor Yellow
        try {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
            Write-Host "Старе завдання видалено успiшно" -ForegroundColor Green
        } catch {
            Write-Host "Не вдалося видалити старе завдання: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    try {
        # Створюємо дію
        $action = New-ScheduledTaskAction -Execute "powershell.exe" `
            -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" `
            -WorkingDirectory (Split-Path $ScriptPath -Parent)
        
        # Створюємо тригер залежно від інтервалу
        switch ($interval) {
            "Daily" {
                $trigger = New-ScheduledTaskTrigger -Daily -At $userTime
            }
            "Weekly" {
                $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday, Tuesday, Wednesday, Thursday, Friday -At $userTime
            }
            "Monthly" {
                # Створюємо тригер для першого числа кожного місяця
                $trigger = New-ScheduledTaskTrigger -Monthly -DaysOfMonth 1 -At $userTime
            }
        }
        
        # Налаштування
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -RestartInterval (New-TimeSpan -Minutes 5) `
            -RestartCount 3 `
            -ExecutionTimeLimit (New-TimeSpan -Hours 2)
        
        # Облікові дані (запуск від імені SYSTEM)
        $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        # Реєструємо завдання
        $task = New-ScheduledTask `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -Principal $principal `
            -Description "Автоматична архiвацiя VETOFFICE системи. Створено $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
        
        Register-ScheduledTask -TaskName $taskName -InputObject $task -Force
        
        Write-Host "`n✓ Завдання успiшно додано до Планувальника!" -ForegroundColor Green
        Write-Host "Назва: $taskName" -ForegroundColor White
        Write-Host "Час: $userTime" -ForegroundColor White
        Write-Host "Iнтервал: $interval" -ForegroundColor White
        
        # Показуємо інформацію про завдання
        Start-Sleep -Seconds 2
        Write-Host "`nПеревiрка створеного завдання..." -ForegroundColor Yellow
        
        try {
            $createdTask = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
            if ($createdTask) {
                Write-Host "✓ Завдання знайдено в Планувальнику" -ForegroundColor Green
                Write-Host "Статус: $($createdTask.State)" -ForegroundColor White
                
                # Отримуємо інформацію про завдання
                $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
                if ($taskInfo) {
                    Write-Host "Останнiй запуск: $($taskInfo.LastRunTime)" -ForegroundColor Gray
                    Write-Host "Наступний запуск: $($taskInfo.NextRunTime)" -ForegroundColor Gray
                }
            }
        } catch {
            Write-Host "Не вдалося знайти створене завдання: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        
        return $true
        
    } catch {
        Write-Host "`n✗ Помилка при створеннi завдання: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Деталi помилки:" -ForegroundColor Yellow
        
        if ($_.Exception.Message -like "*0x80070057*") {
            Write-Host "- Можлива причина: недопустиме ім'я завдання (наприклад, містить спеціальні символи)" -ForegroundColor White
            Write-Host "- Спробуйте використати інший час без спеціальних символів" -ForegroundColor White
        } elseif ($_.Exception.Message -like "*доступ запрещен*" -or $_.Exception.Message -like "*access denied*") {
            Write-Host "- Можлива причина: недостатньо прав" -ForegroundColor White
            Write-Host "- Запустіть PowerShell від імені адміністратора" -ForegroundColor White
        }
        
        Write-Host "`nПеревiрте права адмiнiстратора та доступ до Планувальника завдань." -ForegroundColor Yellow
        return $false
    }
}

function Show-TaskSchedulerInfo {
    Write-Host "`n=== ІНФОРМАЦІЯ ПРО ЗАВДАННЯ В ПЛАНУВАЛЬНИКУ ===" -ForegroundColor Yellow
    
    $tasks = Get-ScheduledTask | Where-Object { $_.TaskName -like "*ARCHIV_VETOFFICE*" }
    
    if ($tasks) {
        Write-Host "Знайдено завдання:" -ForegroundColor Green
        foreach ($task in $tasks) {
            Write-Host "`n  Назва: $($task.TaskName)" -ForegroundColor White
            Write-Host "  Статус: $($task.State)" -ForegroundColor Gray
            
            # Отримуємо детальну інформацію про завдання
            $taskInfo = Get-ScheduledTaskInfo -TaskName $task.TaskName -ErrorAction SilentlyContinue
            if ($taskInfo) {
                Write-Host "Останнiй запуск: $($taskInfo.LastRunTime)" -ForegroundColor Gray
                Write-Host "Наступний запуск: $($taskInfo.NextRunTime)" -ForegroundColor Gray
            }
            
            # Отримуємо тригери
            $triggers = $task.Triggers
            foreach ($trigger in $triggers) {
                if ($trigger.StartBoundary) {
                    Write-Host "  Час запуску: $($trigger.StartBoundary)" -ForegroundColor Gray
                }
            }
            
            # Отримуємо інформацію про дію (що виконується)
            $actions = $task.Actions
            foreach ($action in $actions) {
                if ($action.Execute) {
                    Write-Host "  Виконуваний файл: $($action.Execute)" -ForegroundColor DarkGray
                }
                if ($action.Arguments) {
                    Write-Host "  Аргументи: $($action.Arguments)" -ForegroundColor DarkGray
                }
            }
        }
    } else {
        Write-Host "Завдання архiвацiї VETOFFICE не знайдено в Планувальнику." -ForegroundColor Yellow
        Write-Host "Використовуйте ключ -Schedule для додавання завдання." -ForegroundColor Gray
    }
    
    # Додатково показуємо всі завдання у табличному форматі
    Write-Host "`n=== ЗАГАЛЬНИЙ ПЕРЕЛІК ЗАВДАНЬ ===" -ForegroundColor Yellow
    Get-ScheduledTask | Where-Object { $_.TaskName -like "*ARCHIV_VETOFFICE*" } | 
        Format-Table TaskName, State, @{Name="LastRun"; Expression={$_.LastRunTime}}, @{Name="NextRun"; Expression={$_.NextRunTime}} -AutoSize
}

function Remove-FromTaskScheduler {
    param(
        [string]$TaskName = ""  # Назва завдання для видалення (пусто - показати список)
    )
    
    Write-Host "`n=== ВИДАЛЕННЯ ЗАВДАНЬ З ПЛАНУВАЛЬНИКА ===" -ForegroundColor Yellow
    
    if ([string]::IsNullOrWhiteSpace($TaskName)) {
        # Показуємо всі завдання для видалення
        $tasks = Get-ScheduledTask | Where-Object { $_.TaskName -like "*ARCHIV_VETOFFICE*" }
        
        if (-not $tasks) {
            Write-Host "Завдання архiвацiї VETOFFICE не знайдено." -ForegroundColor Yellow
            return
        }
        
        Write-Host "Знайдено завдання:" -ForegroundColor White
        $i = 1
        $taskList = @()
        foreach ($task in $tasks) {
            Write-Host "  $i. $($task.TaskName)" -ForegroundColor Gray
            $taskList += $task
            $i++
        }
        
        Write-Host "  $i. Всi завдання" -ForegroundColor Gray
        
        $choice = Read-Host "`nОберiть номер завдання для видалення (або Enter для скасування)"
        
        if ([string]::IsNullOrWhiteSpace($choice)) {
            Write-Host "Скасовано." -ForegroundColor Yellow
            return
        }
        
        if ($choice -eq $i) {
            # Видаляємо всі завдання
            Write-Host "Ви впевненi, що хочете видалити ВСI завдання архiвацiї VETOFFICE?" -ForegroundColor Red
            $confirm = Read-Host "Введiть 'YES' для пiдтвердження"
            
            if ($confirm -eq "YES") {
                foreach ($task in $taskList) {
                    try {
                        Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false
                        Write-Host "✓ Видалено: $($task.TaskName)" -ForegroundColor Green
                    } catch {
                        Write-Host "✗ Помилка при видаленнi $($task.TaskName): $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
                Write-Host "`n✓ Всi завдання архiвацiї видалено." -ForegroundColor Green
            } else {
                Write-Host "Скасовано." -ForegroundColor Yellow
            }
        } elseif ($choice -ge 1 -and $choice -lt $i) {
            # Видаляємо одне завдання
            $taskToDelete = $taskList[$choice - 1]
            Write-Host "Ви впевненi, що хочете видалити завдання: $($taskToDelete.TaskName)?" -ForegroundColor Red
            $confirm = Read-Host "Введiть 'YES' для пiдтвердження"
            
            if ($confirm -eq "YES") {
                try {
                    Unregister-ScheduledTask -TaskName $taskToDelete.TaskName -Confirm:$false
                    Write-Host "✓ Завдання видалено: $($taskToDelete.TaskName)" -ForegroundColor Green
                } catch {
                    Write-Host "✗ Помилка при видаленнi: $($_.Exception.Message)" -ForegroundColor Red
                }
            } else {
                Write-Host "Скасовано." -ForegroundColor Yellow
            }
        } else {
            Write-Host "Невiрний вибiр. Скасовано." -ForegroundColor Red
        }
    } else {
        # Видаляємо конкретне завдання
        Write-Host "Ви впевненi, що хочете видалити завдання: $TaskName?" -ForegroundColor Red
        $confirm = Read-Host "Введiть 'YES' для пiдтвердження"
        
        if ($confirm -eq "YES") {
            try {
                Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
                Write-Host "✓ Завдання видалено: $TaskName" -ForegroundColor Green
            } catch {
                Write-Host "✗ Помилка при видаленнi: $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host "Скасовано." -ForegroundColor Yellow
        }
    }
}

# =============================================
# ДОПОМІЖНІ ФУНКЦІЇ
# =============================================


# >>> PROCESS KILL-ON-CLOSE PATCH: BEGIN
# Windows Job Object: kills assigned child processes when this PowerShell process closes.
# This is needed because 7za.exe / WinSCP.com / robocopy.exe can otherwise continue after closing PowerShell.
if (-not ('ArchivJobKillOnClose' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class ArchivJobKillOnClose {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr CreateJobObject(IntPtr lpJobAttributes, string lpName);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetInformationJobObject(
        IntPtr hJob,
        int JobObjectInfoClass,
        IntPtr lpJobObjectInfo,
        uint cbJobObjectInfoLength
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);

    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public IntPtr Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct IO_COUNTERS {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    public const int JobObjectExtendedLimitInformation = 9;
    public const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000;
}
"@
}

$script:ArchivJobHandle = [IntPtr]::Zero

function Initialize-ArchivKillOnCloseJob {
    if ($script:ArchivJobHandle -ne [IntPtr]::Zero) {
        return
    }

    $jobName = 'ARCHIV_VETOFFICE_' + $PID.ToString()
    $script:ArchivJobHandle = [ArchivJobKillOnClose]::CreateJobObject([IntPtr]::Zero, $jobName)

    if ($script:ArchivJobHandle -eq [IntPtr]::Zero) {
        return
    }

    $info = New-Object ArchivJobKillOnClose+JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    $info.BasicLimitInformation.LimitFlags = [ArchivJobKillOnClose]::JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE

    $length = [Runtime.InteropServices.Marshal]::SizeOf($info)
    $ptr = [Runtime.InteropServices.Marshal]::AllocHGlobal($length)

    try {
        [Runtime.InteropServices.Marshal]::StructureToPtr($info, $ptr, $false)
        [void][ArchivJobKillOnClose]::SetInformationJobObject(
            $script:ArchivJobHandle,
            [ArchivJobKillOnClose]::JobObjectExtendedLimitInformation,
            $ptr,
            [uint32]$length
        )
    }
    finally {
        [Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
    }
}

function Add-ProcessToArchivKillOnCloseJob {
    param([System.Diagnostics.Process]$Process)

    if ($null -eq $Process) {
        return
    }

    Initialize-ArchivKillOnCloseJob

    if ($script:ArchivJobHandle -eq [IntPtr]::Zero) {
        return
    }

    try {
    $assigned = [ArchivJobKillOnClose]::AssignProcessToJobObject($script:ArchivJobHandle, $Process.Handle)

    if ($assigned) {
        Write-Log "[JOB] PID=$($Process.Id) assigned to kill-on-close job" -Level "DEBUG" -LogOnly
    } else {
        $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Write-Host "[JOB] FAILED PID=$($Process.Id), Win32Error=$err" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "[JOB] EXCEPTION PID=$($Process.Id): $($_.Exception.Message)" -ForegroundColor Yellow
}
}

Initialize-ArchivKillOnCloseJob
# >>> ARCHIV WATCHDOG PATCH: BEGIN
function Start-ArchivWatchdog {
    param(
        [Parameter(Mandatory=$true)]
        [int]$ParentPid
    )

    try {
        $watchdogScript = Join-Path $env:TEMP ("ARCHIV_VETOFFICE_watchdog_{0}.ps1" -f $ParentPid)

        $scriptText = @"
`$parentPid = $ParentPid
`$processNames = @('7za', '7z', 'WinSCP', 'robocopy')

while (`$true) {
    Start-Sleep -Seconds 2

    `$parent = Get-Process -Id `$parentPid -ErrorAction SilentlyContinue

    if (`$null -eq `$parent) {
        foreach (`$name in `$processNames) {
            Get-Process -Name `$name -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    taskkill /PID `$_.Id /T /F | Out-Null
                } catch {
                }
            }
        }

        Remove-Item -LiteralPath `$PSCommandPath -Force -ErrorAction SilentlyContinue
        break
    }
}
"@

        [System.IO.File]::WriteAllText($watchdogScript, $scriptText, [System.Text.Encoding]::UTF8)

        Start-Process powershell.exe `
            -WindowStyle Hidden `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$watchdogScript`"" `
            -ErrorAction SilentlyContinue | Out-Null

        if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "[WATCHDOG] Started for PowerShell PID=$ParentPid" -Level "DEBUG" -LogOnly }
    }
    catch {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "[WATCHDOG] Failed to start: $($_.Exception.Message)" -Level "WARNING" -LogOnly }
    }
}

Start-ArchivWatchdog -ParentPid $PID
# <<< ARCHIV WATCHDOG PATCH: END
# <<< PROCESS KILL-ON-CLOSE PATCH: END
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [int]$SeparatorLength = 100,
        [switch]$NoTimestamp,  # Новий параметр для вiдключення timestamp
        [switch]$LogOnly        # Новий параметр: записувати тiльки в лог-файл, не в консоль
    )
    
    # Перевірка рівня логування
    $logLevels = @{"DEBUG"=0; "INFO"=1; "WARNING"=2; "ERROR"=3; "SUCCESS"=4}
    
    # Отримуємо поточний рівень логування з глобальної змінної
    $currentLogLevel = if ($global:LogLevel -and $logLevels.ContainsKey($global:LogLevel)) { 
        $logLevels[$global:LogLevel] 
    } else { 
        1 # Значення за замовчуванням - INFO
    }
    
    $messageLevel = if ($logLevels.ContainsKey($Level)) { 
        $logLevels[$Level] 
    } else { 
        1 # Значення за замовчуванням - INFO
    }
    
    # Пропускаємо повідомлення нижчого рівня
    if ($messageLevel -lt $currentLogLevel) {
        return
    }
    
    # Обробка спеціальних повідомлень-роздільників
    if ($Message -eq "=" -or $Message -eq "===") {
        # Генеруємо роздільник з 100 знаками "="
        $separator = "=" * 100
        
        # Для консолi використовуємо короткий формат без дати/часу.
        
        # У файл логу нижче записується повний $logEntry з timestamp.
        
        if ($NoTimestamp) {
        
            $consoleEntry = $Message
        
        } else {
        
            $consoleEntry = "[$Level] $Message"
        
        }

        
        # Виводимо в консоль тiльки якщo не LogOnly
        if (-not $LogOnly) {
            Write-Host $separator -ForegroundColor White
        }
        
        try {
            if (-not (Test-Path $logPath)) {
                New-Item -ItemType Directory -Path $logPath -Force | Out-Null
            }
            $separator | Out-File -FilePath $global:logFile -Append -Encoding UTF8
        } catch {
            if (-not $LogOnly) {
                Write-Host "Помилка запису у файл логу: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        return
    }
    
    # Обробка заголовків "--- текст ---"
    if ($Message -match "^--- .* ---$") {
        # Для підзаголовків --- ---
        if (-not $LogOnly) {
            Write-Host $Message -ForegroundColor Cyan
        }
        
        try {
            if (-not (Test-Path $logPath)) {
                New-Item -ItemType Directory -Path $logPath -Force | Out-Null
            }
            $Message | Out-File -FilePath $global:logFile -Append -Encoding UTF8
        } catch {
            if (-not $LogOnly) {
                Write-Host "Помилка запису у файл логу: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        return
    }
    
    # Обробка заголовків "=== текст ==="
    if ($Message -match "^=== .* ===$") {
        # Для заголовків === ===
        if (-not $LogOnly) {
            Write-Host $Message -ForegroundColor Yellow
        }
        
        try {
            if (-not (Test-Path $logPath)) {
                New-Item -ItemType Directory -Path $logPath -Force | Out-Null
            }
            $Message | Out-File -FilePath $global:logFile -Append -Encoding UTF8
        } catch {
            if (-not $LogOnly) {
                Write-Host "Помилка запису у файл логу: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        return
    }
    
    # Звичайні повідомлення
    if ($NoTimestamp) {
        # Повідомлення без timestamp (для інформаційних блоків)
        $logEntry = $Message
        
        # Для NoTimestamp повідомлень з LogOnly - додаємо timestamp при записі в лог
        if ($LogOnly) {
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $logEntry = "[$timestamp] [$Level] $Message"
        }
    } else {
        # Звичайні повідомлення з timestamp
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "[$timestamp] [$Level] $Message"
    }
    
    # Для консолi використовуємо короткий формат без дати/часу.
    
    # У файл логу нижче записується повний $logEntry з timestamp.
    
    if ($NoTimestamp) {
    
        $consoleEntry = $Message
    
    } else {
    
        $consoleEntry = "[$Level] $Message"
    
    }

    
    # Виводимо в консоль тiльки якщo не LogOnly
    if (-not $LogOnly) {
        switch ($Level) {
            "SUCCESS" { Write-Host $consoleEntry -ForegroundColor Green }
            "ERROR"   { Write-Host $consoleEntry -ForegroundColor Red }
            "WARNING" { Write-Host $consoleEntry -ForegroundColor Yellow }
            "DEBUG"   { Write-Host $consoleEntry -ForegroundColor Gray }
            default   { Write-Host $consoleEntry -ForegroundColor White }
        }
    }
    
    # Завжди записуємо в лог-файл
    try {
        if (-not (Test-Path $logPath)) {
            New-Item -ItemType Directory -Path $logPath -Force | Out-Null
        }
        $logEntry | Out-File -FilePath $global:logFile -Append -Encoding UTF8
    } catch {
        if (-not $LogOnly) {
            Write-Host "Помилка запису у файл логу: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

function Test-PathWithLog {
    param(
        [string]$Path,
        [string]$Description
    )
    
    # Визначаємо, чи це каталог призначення (архіви, логи, тощо)
    $isDestinationPath = ($Description -like "*архiв*" -or 
                         $Description -like "*логiв*" -or 
                         $Path -eq $bazaPaths.Destination -or
                         $Path -eq $logPath -or
                         $Path -eq $toolsPath -or
                         $Path -eq $archivPath)
    
    if (Test-Path $Path) {
        Write-Log "$Description знайдено: $Path" -Level "DEBUG"
        return $true
    } else {
        # Для каталогів призначення - створюємо автоматично
        if ($isDestinationPath) {
            try {
                New-Item -ItemType Directory -Path $Path -Force | Out-Null
                Write-Log "$Description не знайдено, створено автоматично: $Path" -Level "SUCCESS"
                return $true
            } catch {
                Write-Log "$Description не знайдено i не вдалося створити: $Path" -Level "ERROR"
                return $false
            }
        } else {
            # Для всіх інших шляхів (джерела даних) - показуємо помилку
            Write-Log "$Description не знайдено: $Path" -Level "ERROR"
            return $false
        }
    }
}

function Show-PathCheckSummary {
    param(
        [array]$CheckedPaths,
        [bool]$AllPathsExist
    )
    
    if ($AllPathsExist) {
        Write-Log "Всi необхiднi шляхи перевiрено успiшно" -Level "SUCCESS"
        Write-Log "==="
    } else {
        Write-Log "Знайдено помилки в шляхах - див. вище" -Level "ERROR"
        Write-Log "==="
    }
}

function Remove-OldFiles {
    param(
        [string]$Path,
        [string]$Filter,
        [int]$KeepCount,
        [string]$FileType
    )
    
    # Для логів завжди виконуємо перевірку, для архівів - тільки якщо увімкнено
    $isLogFile = $FileType -like "*логiв*"
    
    if (-not $enableArchiveDeletion -and -not $isLogFile) {
        # Для архівів - логуємо тільки один раз на початку секції
        if ($FileType -like "*архiвiв*" -and -not $script:archiveDeletionLogged) {
            Write-Log "Видалення старих архiвiв вимкнено в налаштуваннях" -Level "INFO"
            $script:archiveDeletionLogged = $true
        }
        return $true
    }
    
    Write-Log "Видалення старих $FileType (залишити $KeepCount): $Path"
    
    if (-not (Test-Path $Path)) {
        Write-Log "Шлях не знайдено: $Path" -Level "WARNING"
        return $false
    }
    
    try {
        $files = Get-ChildItem -Path $Path -Filter $Filter -File | 
                 Sort-Object LastWriteTime -Descending
        
        if ($files.Count -le $KeepCount) {
            # Логуємо тільки для лог-файлів, для архівів - тільки якщо увімкнено
            if ($isLogFile -or $enableArchiveDeletion) {
                Write-Log "Кiлькiсть файлiв ($($files.Count)) не перевищує лiмiт ($KeepCount)" -Level "INFO"
            }
            return $true
        }
        
        # Якщо видалення вимкнено для архівів і це не лог-файли - не видаляємо
        if (-not $enableArchiveDeletion -and -not $isLogFile) {
            return $true
        }
        
        $filesToDelete = $files | Select-Object -Skip $KeepCount
        $deletedCount = 0
        
        foreach ($file in $filesToDelete) {
            try {
                Remove-Item $file.FullName -Force
                Write-Log "Видалено: $($file.Name)" -Level "SUCCESS"
                $deletedCount++
            } catch {
                Write-Log "Помилка при видаленнi $($file.Name): $($_.Exception.Message)" -Level "ERROR"
            }
        }
        
        if ($deletedCount -gt 0) {
            Write-Log "Успiшно видалено $deletedCount $FileType" -Level "SUCCESS"
        }
        
        return $true
    } catch {
        Write-Log "Помилка при видаленнi ${FileType}: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}


function Invoke-ArchivArchiveRetention {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,

        [Parameter(Mandatory=$true)]
        [string]$ArchiveType,

        [string]$DisplayName = "",

        [int]$KeepCount = 31,

        [int]$KeepDays = 0
    )

    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        switch ($ArchiveType) {
            "Model" { $DisplayName = "VETOFFICE" }
            "Blog"  { $DisplayName = "BLOG" }
            default { $DisplayName = $ArchiveType.ToUpperInvariant() }
        }
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Log "Каталог архiвiв не знайдено: $Path" -Level "WARNING"
        return $false
    }

    if ($KeepCount -lt 1) {
        Write-Log "Некоректне значення KeepCount для ${ArchiveType}: $KeepCount. Використано 1." -Level "WARNING"
        $KeepCount = 1
    }

    try {
        $archives = @(Get-ChildItem -LiteralPath $Path -Filter "*.mdz" -File -ErrorAction Stop |
            Sort-Object LastWriteTime -Descending)

        $hashes = @(Get-ChildItem -LiteralPath $Path -Filter "*.sha512" -File -ErrorAction SilentlyContinue)

        Write-Log "" -NoTimestamp
        Write-Log "--- $DisplayName ---"
        Write-Log "Каталог: $Path" -Level "INFO" -LogOnly
        Write-Log "Архiвiв: $($archives.Count) | SHA512: $($hashes.Count) | Лiмiт: $KeepCount" -Level "INFO"

        if ($KeepDays -gt 0) {
            Write-Log "Лiмiт за вiком: $KeepDays дн." -Level "INFO"
        }

        if ($archives.Count -eq 0) {
            Write-Log "Архiвiв не знайдено" -Level "INFO"
            return $true
        }

        $keepSet = New-Object 'System.Collections.Generic.HashSet[string]'
        $archivesToKeep = @($archives | Select-Object -First $KeepCount)

        foreach ($archive in $archivesToKeep) {
            [void]$keepSet.Add($archive.FullName.ToLowerInvariant())
        }

        $archivesToDelete = @()

        foreach ($archive in $archives) {
            $archiveKey = $archive.FullName.ToLowerInvariant()

            if (-not $keepSet.Contains($archiveKey)) {
                $archivesToDelete += $archive
            }
        }

        # Optional age-based cleanup, but never delete the latest KeepCount because of age.
        if ($KeepDays -gt 0 -and $archives.Count -gt $KeepCount) {
            $cutoffDate = (Get-Date).AddDays(-1 * $KeepDays)
            foreach ($archive in $archives) {
                $archiveKey = $archive.FullName.ToLowerInvariant()
                if (-not $keepSet.Contains($archiveKey) -and $archive.LastWriteTime -lt $cutoffDate -and ($archivesToDelete.FullName -notcontains $archive.FullName)) {
                    $archivesToDelete += $archive
                }
            }
        }

        $deletedArchives = 0
        $deletedHashes = 0
        $plannedArchives = 0
        $plannedHashes = 0

        foreach ($archive in $archivesToDelete) {
            $hashPath = "$($archive.FullName).sha512"

            if ($global:DryRun) {
                Write-Log "DRY-RUN: буде видалено архiв: $($archive.Name)" -Level "WARNING"
                $plannedArchives++

                if (Test-Path -LiteralPath $hashPath) {
                    Write-Log "DRY-RUN: буде видалено SHA512: $(Split-Path $hashPath -Leaf)" -Level "WARNING"
                    $plannedHashes++
                }

                continue
            }

            try {
                Remove-Item -LiteralPath $archive.FullName -Force -ErrorAction Stop
                Write-Log "Видалено архiв: $($archive.Name)" -Level "SUCCESS"
                $deletedArchives++
            } catch {
                Write-Log "Помилка видалення архiву $($archive.Name): $($_.Exception.Message)" -Level "ERROR"
            }

            if (Test-Path -LiteralPath $hashPath) {
                try {
                    Remove-Item -LiteralPath $hashPath -Force -ErrorAction Stop
                    Write-Log "Видалено SHA512: $(Split-Path $hashPath -Leaf)" -Level "SUCCESS"
                    $deletedHashes++
                } catch {
                    Write-Log "Помилка видалення SHA512 $(Split-Path $hashPath -Leaf): $($_.Exception.Message)" -Level "ERROR"
                }
            }
        }

        # Orphan SHA512 cleanup: hash exists, archive does not.
        $orphanHashes = @()
        foreach ($hash in $hashes) {
            $archivePath = $hash.FullName -replace '\.sha512$', ''
            if (-not (Test-Path -LiteralPath $archivePath)) {
                $orphanHashes += $hash
            }
        }

        foreach ($hash in $orphanHashes) {
            # Список хешів формується до видалення парних .sha512.
            # Тому файл міг бути вже коректно видалений разом з архівом — це не помилка.
            if (-not (Test-Path -LiteralPath $hash.FullName)) {
                Write-Log "Orphan SHA512 вже видалено раніше: $($hash.Name)" -Level "DEBUG" -LogOnly
                continue
            }

            if ($global:DryRun) {
                Write-Log "DRY-RUN: буде видалено orphan SHA512: $($hash.Name)" -Level "WARNING"
                $plannedHashes++
                continue
            }

            try {
                Remove-Item -LiteralPath $hash.FullName -Force -ErrorAction Stop
                Write-Log "Видалено orphan SHA512: $($hash.Name)" -Level "SUCCESS"
                $deletedHashes++
            } catch [System.Management.Automation.ItemNotFoundException] {
                Write-Log "Orphan SHA512 вже видалено раніше: $($hash.Name)" -Level "DEBUG" -LogOnly
            } catch {
                Write-Log "Помилка видалення orphan SHA512 $($hash.Name): $($_.Exception.Message)" -Level "ERROR"
            }
        }

        if ($global:DryRun) {
            if ($plannedArchives -eq 0 -and $plannedHashes -eq 0) {
                Write-Log "DRY-RUN: видалення не потрiбне" -Level "INFO"
            } else {
                Write-Log "DRY-RUN: буде видалено архiвiв: $plannedArchives | SHA512: $plannedHashes" -Level "WARNING"
            }
        } else {
            if ($deletedArchives -eq 0 -and $deletedHashes -eq 0) {
                Write-Log "Видалення не потрiбне" -Level "INFO"
            } else {
                Write-Log "Видалено архiвiв: $deletedArchives | SHA512: $deletedHashes" -Level "SUCCESS"
            }
        }

        return $true
    } catch {
        Write-Log "Помилка retention архiвiв ${ArchiveType}: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Sync-Folders {
    param(
        [string]$SourcePath,
        [string]$DestinationPath,
        [string]$SyncType = "LOCAL",  # "LOCAL" або "NETWORK"
        [switch]$LogAlways = $false
    )
    
    # Заголовок залежно від типу синхронізації
    $headerTitle = if ($SyncType -eq "NETWORK") { 
        "--- МЕРЕЖЕВА СИНХРОНІЗАЦІЯ ФАЙЛІВ BAZA ---"
    } else { 
        "--- ЛОКАЛЬНА СИНХРОНІЗАЦІЯ ФАЙЛІВ BAZA ---" 
    }
    
    Write-Log $headerTitle -Level "INFO"
    Write-Log "Джерело: $SourcePath" -Level "INFO"
    Write-Log "Призначення: $DestinationPath" -Level "INFO"
    
    # Перевірка джерельної папки
    if (-not (Test-Path $SourcePath)) {
        Write-Log "ДЖЕРЕЛЬНА ПАПКА НЕ ЗНАЙДЕНА: $SourcePath" -Level "ERROR"
        return $false
    }
    
    # Унікальний ідентифікатор сесії
    $sessionId = Get-Date -Format "yyyyMMdd_HHmmss"
    $logType = if ($SyncType -eq "NETWORK") { "network" } else { "local" }
    $tempLog = "$env:TEMP\robocopy_${logType}_temp_$sessionId.log"
    
    try {
        # === ПІДГОТОВКА ===
        Write-Log "Підготовка до синхронізації..." -Level "INFO"
        
        # Нормалізація шляхів
        $SourcePath = $SourcePath.TrimEnd('\')
        $DestinationPath = $DestinationPath.TrimEnd('\')
        
        # Створюємо цільову папку, якщо не існує
        if (-not (Test-Path $DestinationPath)) {
            try {
                New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
                Write-Log "Створено цiльову папку: $DestinationPath" -Level "SUCCESS"
            } catch {
                Write-Log "Не вдалося створити цiльову папку: $($_.Exception.Message)" -Level "ERROR"
                return $false
            }
        }
        
        # === ПАРАМЕТРИ ROBOCOPY ===
        # Базові параметри однакові для обох типів
        $robocopyBaseParams = @(
            "/E",                    # Включаючи підпапки
            "/COPY:DAT",             # Копіювати: Дані, Атрибути, Мітки часу
            "/DCOPY:T",              # Мітки часу для папок
            "/FFT",                  # FAT-час (2 секунди точності)
            "/DST",                  # Компенсація літнього/зимового часу
            "/XO",                   # Тільки новіші файли
            "/XJ",                   # Ігнорувати junction points
            "/Z",                    # Режим перезапуску
            "/TBD",                  # Чекати на мережеві ресурси
            "/NP",                   # Не показувати відсоток виконання
            "/MT:8",                 # 8 потоків
            "/UNICODE",              # Unicode підтримка
            "/V",                    # Детальний вивід
            "/TS",                   # Мітки часу у виводі
            "/FP",                   # Повні шляхи файлів
            "/NDL",                  # Без списку каталогів
            "/NS",                   # Без розмірів файлів
            "/NC",                   # Без класів файлів
            "/LOG:`"$tempLog`""      # Логування у тимчасовий файл
        )
        
        # Додаткові параметри залежно від типу
        $robocopyAdditionalParams = if ($SyncType -eq "NETWORK") {
            @(
                "/R:5",              # 5 спроб для мережі
                "/W:10"              # 10 секунд очікування для мережі
            )
        } else {
            @(
                "/R:3",              # 3 спроб для локальної
                "/W:5"               # 5 секунд очікування для локальної
            )
        }
        
        # Об'єднуємо всі параметри
        $robocopyParams = @("`"$SourcePath`"", "`"$DestinationPath`"") + 
                          $robocopyBaseParams + 
                          $robocopyAdditionalParams
        
        Write-Log "Запуск синхронізації..." -Level "INFO"
        
        $startTime = Get-Date
        
        # Запуск Robocopy
        $process = Start-Process robocopy.exe `
            -ArgumentList $robocopyParams `
            -WindowStyle Hidden `
            -PassThru `
            -ErrorAction Stop
        Add-ProcessToArchivKillOnCloseJob -Process $process
        $process.WaitForExit()
        
        $endTime = Get-Date
        $exitCode = $process.ExitCode
        $duration = $endTime - $startTime
        
        # === ПОКРАЩЕНИЙ АНАЛІЗ РЕЗУЛЬТАТІВ ===
        Write-Log "Robocopy завершено. Код: $exitCode, Час: $([math]::Round($duration.TotalSeconds, 1)) сек" -Level "INFO"
        
        # Розшифровка коду виходу
        $exitCodeInfo = @{
            0 = "УСПІХ - без змін"
            1 = "УСПІХ - деякі файли не оброблені (немає змін)"
            2 = "ДОДАТКОВІ ФАЙЛИ"
            4 = "НЕВІДПОВІДНІ ПАПКИ"
            8 = "ПОМИЛКИ КОПІЮВАННЯ"
            16 = "ПОМИЛКИ СЕРВЕРА"
        }
        
        if ($exitCodeInfo.ContainsKey($exitCode)) {
            $exitMessage = $exitCodeInfo[$exitCode]
        } else {
            $exitMessage = "Невідомий код ($exitCode)"
        }
        Write-Log "Результат: $exitMessage" -Level "INFO"
        
        $hasChanges = $false
        $hasErrors = $false
        $copiedFiles = @()
        $errorLines = @()
        $copiedCount = 0
        $skippedCount = 0
        $mismatchCount = 0
        $failedCount = 0
        
        if (Test-Path $tempLog -PathType Leaf) {
            $logContent = Get-Content $tempLog
            
            # Детальний аналіз логу
            foreach ($line in $logContent) {
                # Файли, які були скопійовані
                if ($line -match '(изменен|новая|newer|changed)\s+(\d+)') {
                    $hasChanges = $true
                    $fileCount = [int]$matches[2]
                    $copiedCount += $fileCount
                    
                    if ($line -match '\\[^\\]+$') {
                        $copiedFiles += $matches[0].Trim('\')
                    }
                }
                
                # Пропущені файли
                if ($line -match '(пропущен|skipped|extra)\s+(\d+)') {
                    $skippedCount += [int]$matches[2]
                }
                
                # Невідповідності
                if ($line -match '(mismatch|несоответств)\s+(\d+)') {
                    $mismatchCount += [int]$matches[2]
                }
                
                # Помилки
                if ($line -match 'ERROR|СБОЙ|FAILED|ошибка') {
                    $hasErrors = $true
                    $errorLines += $line
                }
                
                # Підсумкова статистика
                if ($line -match 'Файлов\s*:\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)') {
                    $totalFiles = [int]$matches[1]
                    $copied = [int]$matches[2]
                    $skipped = [int]$matches[3]
                    $failed = [int]$matches[4]
                    
                    if ($copied -gt 0) {
                        $hasChanges = $true
                        $copiedCount = $copied
                    }
                    $failedCount = $failed
                }
            }
        }
        
        # Перевірка на критичні помилки (код >= 8)
        if ($exitCode -ge 8) {
            $hasErrors = $true
        }
        
        # === ЗБЕРЕЖЕННЯ ЛОГУ ===
        $needSaveLog = $LogAlways -or $hasChanges -or $hasErrors -or ($exitCode -gt 0)
        
        # Шлях для лог-файлів
        $logBasePath = Join-Path $logPath "SYNC_LOGS"
        if (-not (Test-Path $logBasePath)) {
            New-Item -Path $logBasePath -ItemType Directory -Force | Out-Null
        }
        
        if ($needSaveLog) {
            # Формування імені лог -файлу
            $logTypeName = if ($hasErrors) { "ERROR" } 
                          elseif ($hasChanges) { "CHANGES" } 
                          elseif ($exitCode -eq 0) { "NOCHANGES" }
                          else { "INFO" }
            
            $logFileName = "robocopy_${SyncType}_${logTypeName}_${sessionId}.log"
            $finalLogPath = Join-Path $logBasePath $logFileName
            
            # Запис логу
            if (Test-Path $tempLog) {
                Copy-Item $tempLog $finalLogPath -Force
                Write-Log "Лог синхронізації збережено: $finalLogPath" -Level "INFO" -LogOnly
            }
        }
        
        # Видалення тимчасового логу
        if (Test-Path $tempLog) {
            Remove-Item $tempLog -Force -ErrorAction SilentlyContinue
        }
        
        # === ПОВЕРНЕННЯ РЕЗУЛЬТАТУ ===
        # Коди 0-7 вважаються успішними для Robocopy
        return ($exitCode -le 7)
    }
    catch {
        # Обробка критичних помилок
        $errorMsg = $_.Exception.Message
        
        Write-Log "КРИТИЧНА ПОМИЛКА СИНХРОНІЗАЦІЇ ($SyncType): $errorMsg" -Level "ERROR"
        
        # Очищення
        if (Test-Path $tempLog) {
            Remove-Item $tempLog -Force -ErrorAction SilentlyContinue
        }
        
        return $false
    }
}

# =============================================
# >>> CREDENTIAL MANAGER SECRETS PATCH: BEGIN
function Initialize-ArchivCredentialReader {
    if ("ArchivCredentialManager.NativeMethods" -as [type]) {
        return
    }

    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace ArchivCredentialManager {
    public static class NativeMethods {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct CREDENTIAL {
            public UInt32 Flags;
            public UInt32 Type;
            public string TargetName;
            public string Comment;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
            public UInt32 CredentialBlobSize;
            public IntPtr CredentialBlob;
            public UInt32 Persist;
            public UInt32 AttributeCount;
            public IntPtr Attributes;
            public string TargetAlias;
            public string UserName;
        }

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool CredRead(string target, UInt32 type, UInt32 reservedFlag, out IntPtr credentialPtr);

        [DllImport("advapi32.dll", SetLastError = true)]
        public static extern void CredFree(IntPtr buffer);
    }
}
"@
}

function Get-ArchivWindowsCredential {
    param([string]$Target)

    if ([string]::IsNullOrWhiteSpace($Target)) {
        return $null
    }

    Initialize-ArchivCredentialReader

    foreach ($type in @(1, 2)) {
        $credentialPtr = [IntPtr]::Zero

        try {
            $found = [ArchivCredentialManager.NativeMethods]::CredRead($Target, [uint32]$type, 0, [ref]$credentialPtr)

            if (-not $found -or $credentialPtr -eq [IntPtr]::Zero) {
                continue
            }

            $credential = [Runtime.InteropServices.Marshal]::PtrToStructure(
                $credentialPtr,
                [type][ArchivCredentialManager.NativeMethods+CREDENTIAL]
            )

            $password = ""
            if ($credential.CredentialBlob -ne [IntPtr]::Zero -and $credential.CredentialBlobSize -gt 0) {
                $password = [Runtime.InteropServices.Marshal]::PtrToStringUni(
                    $credential.CredentialBlob,
                    [int]($credential.CredentialBlobSize / 2)
                )
            }

            return [PSCustomObject]@{
                Target   = $Target
                Username = $credential.UserName
                Password = $password
                Type     = $type
            }
        }
        finally {
            if ($credentialPtr -ne [IntPtr]::Zero) {
                [ArchivCredentialManager.NativeMethods]::CredFree($credentialPtr)
            }
        }
    }

    return $null
}

function Get-ArchivCredentialPassword {
    param(
        [string]$Target,
        [string]$FallbackPassword = ""
    )

    if (-not [string]::IsNullOrWhiteSpace($Target)) {
        $credential = Get-ArchivWindowsCredential -Target $Target

        if ($credential -and -not [string]::IsNullOrWhiteSpace($credential.Password)) {
            Write-Log "Секрет отримано з Windows Credential Manager (Target: $Target)" -Level "DEBUG" -LogOnly
            return $credential.Password
        }

        Write-Log "Секрет не знайдено в Windows Credential Manager (Target: $Target)" -Level "WARNING" -LogOnly
    }

    if (-not [string]::IsNullOrWhiteSpace($FallbackPassword)) {
        Write-Log "Використовується fallback-секрет з конфігурації" -Level "WARNING" -LogOnly
        return $FallbackPassword
    }

    return $null
}

function Get-ArchivConfigValue {
    param(
        [string]$Name,
        $DefaultValue = $null
    )

    $variable = Get-Variable -Name $Name -ErrorAction SilentlyContinue
    if ($null -ne $variable) {
        return $variable.Value
    }

    return $DefaultValue
}

function Get-ArchivArchivePassword {
    $enabled = Get-ArchivConfigValue -Name "enableArchivePassword" -DefaultValue $false

    if (-not $enabled) {
        return $null
    }

    $target = Get-ArchivConfigValue -Name "archivePasswordCredentialTarget" -DefaultValue "ARCHIV_VETOFFICE_ARCHIVE_PASSWORD"
    return Get-ArchivCredentialPassword -Target $target
}

function Get-ArchivSftpPassword {
    $target = Get-ArchivConfigValue -Name "sftpPasswordCredentialTarget" -DefaultValue "ARCHIV_VETOFFICE_SFTP_PASSWORD"
    $fallback = Get-ArchivConfigValue -Name "Password" -DefaultValue ""
    return Get-ArchivCredentialPassword -Target $target -FallbackPassword $fallback
}

function Get-ArchivNetworkPassword {
    $target = $null
    $fallback = ""

    if ($networkCopyConfig) {
        if ($networkCopyConfig.ContainsKey("PasswordCredentialTarget")) {
            $target = $networkCopyConfig.PasswordCredentialTarget
        }

        if ($networkCopyConfig.ContainsKey("Password")) {
            $fallback = $networkCopyConfig.Password
        }
    }

    if ([string]::IsNullOrWhiteSpace($target)) {
        $target = "ARCHIV_VETOFFICE_NETWORK_PASSWORD"
    }

    return Get-ArchivCredentialPassword -Target $target -FallbackPassword $fallback
}

function Resolve-ArchivSftpUrl {
    param([string]$RepositorySFTPUrl)

    $loginValue = Get-ArchivConfigValue -Name "Login" -DefaultValue ""
    $passwordValue = Get-ArchivSftpPassword

    if ([string]::IsNullOrWhiteSpace($loginValue)) {
        Write-Log "SFTP логiн не встановлено" -Level "ERROR"
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($passwordValue)) {
        Write-Log "SFTP пароль не знайдено в Windows Credential Manager" -Level "ERROR"
        return $null
    }

    # Якщо URL вже містить user/password або user@host, залишаємо як є.
    if ($RepositorySFTPUrl -match '^[a-zA-Z]+://[^/]*@') {
        return $RepositorySFTPUrl
    }

    $encodedLogin = [Uri]::EscapeDataString($loginValue)
    $encodedPassword = [Uri]::EscapeDataString($passwordValue)

    return ($RepositorySFTPUrl -replace '^(sftp://)', ('${1}' + "$encodedLogin`:$encodedPassword@"))
}
# <<< CREDENTIAL MANAGER SECRETS PATCH: END
# ФУНКЦІЇ АРХІВАЦІЇ
# =============================================


function Get-PathSizeBytes {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        Write-Log "Не вдалося порахувати розмiр: шлях не знайдено: $Path" -Level "ERROR"
        return $null
    }

    try {
        $item = Get-Item -Path $Path -ErrorAction Stop

        if (-not $item.PSIsContainer) {
            return [int64]$item.Length
        }

        $totalBytes = [int64]0
        Get-ChildItem -Path $Path -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
            $totalBytes += [int64]$_.Length
        }

        return $totalBytes
    } catch {
        Write-Log "Помилка пiдрахунку розмiру '$Path': $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Format-FileSize {
    param(
        [Parameter(Mandatory=$true)]
        [Int64]$Bytes
    )

    if ($Bytes -ge 1TB) { return ("{0:N2} TB" -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ("{0:N2} GB" -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:N2} MB" -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ("{0:N2} KB" -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

function Test-FreeSpaceForArchive {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourcePath,

        [Parameter(Mandatory=$true)]
        [string]$ArchivePath,

        [double]$ReserveMultiplier = 1.2,
        [double]$MinFreeSpaceGB = 20,
        [string]$ArchiveType = "ARCHIVE",
        [string]$ArchivePasswordSwitch = "",
        [int]$TimeoutSeconds = 600
    )

    Write-Log "Перевiрка вiльного мiсця перед архiвацiєю..." -Level "DEBUG" -LogOnly

    $sourceSizeBytes = Get-PathSizeBytes -Path $SourcePath
    if ($null -eq $sourceSizeBytes) {
        Write-Log "Перевiрку вiльного мiсця не пройдено: не вдалося визначити розмiр джерела" -Level "ERROR"
        return $false
    }

    try {
        $archiveFullPath = [System.IO.Path]::GetFullPath($ArchivePath)
        $archiveRoot = [System.IO.Path]::GetPathRoot($archiveFullPath)

        if ([string]::IsNullOrWhiteSpace($archiveRoot)) {
            Write-Log "Не вдалося визначити диск/корiнь для архiву: $ArchivePath" -Level "ERROR"
            return $false
        }

        $drive = New-Object System.IO.DriveInfo($archiveRoot)
        $freeBytes = [int64]$drive.AvailableFreeSpace
    } catch {
        Write-Log "Помилка визначення вiльного мiсця для '$ArchivePath': $($_.Exception.Message)" -Level "ERROR"
        return $false
    }

    $requiredBySourceBytes = [int64]($sourceSizeBytes * $ReserveMultiplier)
    $requiredMinBytes = [int64]($MinFreeSpaceGB * 1GB)
    $requiredBytes = [Math]::Max($requiredBySourceBytes, $requiredMinBytes)

    Write-Log "Розмiр джерела: $(Format-FileSize -Bytes $sourceSizeBytes)" -Level "INFO"
    Write-Log "Вiльно на диску архiву: $(Format-FileSize -Bytes $freeBytes)" -Level "INFO"
    

    if ($freeBytes -lt $requiredBytes) {
        $missingBytes = $requiredBytes - $freeBytes
        Write-Log "Недостатньо мiсця для архiвацiї. Не вистачає: $(Format-FileSize -Bytes $missingBytes)" -Level "ERROR"
        return $false
    }

    Write-Log "Перевiрка вiльного мiсця пройдена" -Level "DEBUG" -LogOnly
    return $true
}

function Test-ArchiveIntegrity {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ArchivePath,

        [Parameter(Mandatory=$true)]
        [string]$ArcPath,

        [string]$ArchiveType = "ARCHIVE",
        [string]$ArchivePasswordSwitch = "",
        [int]$TimeoutSeconds = 600
    )

    if ($global:DryRun) {
        Write-Log "DRY-RUN: перевiрка архiву пропущена: $(Split-Path $ArchivePath -Leaf)" -Level "WARNING"
        return $true
    }

    if (-not (Test-Path -LiteralPath $ArchivePath)) {
        Write-Log "Архiв для перевiрки не знайдено: $ArchivePath" -Level "ERROR"
        return $false
    }

    if (-not (Test-Path -LiteralPath $ArcPath)) {
        Write-Log "7-Zip не знайдено для перевiрки архiву: $ArcPath" -Level "ERROR"
        return $false
    }

    Write-Log "Перевiрка архiву 7-Zip: $(Split-Path $ArchivePath -Leaf)" -Level "INFO"

    try {
        Set-ArchivWindowTitle -Stage "Тест архiву $ArchiveType"

        $testParams = "t -y -bb0"

        if (-not [string]::IsNullOrWhiteSpace($ArchivePasswordSwitch)) {
            $testParams = "$testParams $ArchivePasswordSwitch"
        }

        $arguments = "$testParams `"$ArchivePath`""

        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $ArcPath
        $processInfo.Arguments = $arguments
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        $processInfo.RedirectStandardInput = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $process.Start() | Out-Null
        Add-ProcessToArchivKillOnCloseJob -Process $process

        try {
            # Якщо 7-Zip спробує щось запитати інтерактивно, відправляємо порожній ввід і закриваємо stdin.
            $process.StandardInput.WriteLine("")
            $process.StandardInput.Close()
        } catch {
        }

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch {}
            Write-Log "Перевiрка архiву перевищила timeout $TimeoutSeconds сек: $ArchivePath" -Level "ERROR"
            return $false
        }

        $standardOutput = $process.StandardOutput.ReadToEnd()
        $errorOutput = $process.StandardError.ReadToEnd()

        if ($process.ExitCode -eq 0) {
            Write-Log "Перевiрка архiву пройдена: $(Split-Path $ArchivePath -Leaf)" -Level "SUCCESS"
            return $true
        }

        Write-Log "Помилка перевiрки архiву 7-Zip (код: $($process.ExitCode)): $ArchivePath" -Level "ERROR"

        if (-not [string]::IsNullOrWhiteSpace($errorOutput)) {
            Write-Log "7-Zip test stderr: $errorOutput" -Level "ERROR"
        }

        if (-not [string]::IsNullOrWhiteSpace($standardOutput)) {
            Write-Log "7-Zip test stdout: $standardOutput" -Level "ERROR" -LogOnly
        }

        return $false
    } catch {
        Write-Log "Помилка перевiрки архiву: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}
function New-Archive {
    param(
        [string]$SourcePath,
        [string]$ArchivePath,
        [string]$ArchiveName,
        [string]$ArcPath,
        [string]$ArcParams,
        [double]$ReserveMultiplier = 1.2,
        [double]$MinFreeSpaceGB = 20,
        [string]$ArchiveType = "ARCHIVE",
        [string]$ArchivePasswordSwitch = "",
        [int]$TimeoutSeconds = 600
    )
     
    $archiveDir = Split-Path $ArchivePath -Parent
    if (-not (Test-Path $archiveDir)) {
        try {
            New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
            Write-Log "Каталог створено: $archiveDir" -Level "SUCCESS"
        } catch {
            Write-Log "Помилка при створеннi каталогу: $($_.Exception.Message)" -Level "ERROR"
            return $false
        }
    }
    
    if (-not (Test-Path $SourcePath)) {
        Write-Log "Джерело не знайдено: $SourcePath" -Level "ERROR"
        return $false
    }

    if (-not (Test-FreeSpaceForArchive -SourcePath $SourcePath -ArchivePath $ArchivePath -ReserveMultiplier $ReserveMultiplier -MinFreeSpaceGB $MinFreeSpaceGB)) {
        Write-Log "Архiвацiю скасовано через недостатнiй резерв вiльного мiсця: $ArchiveName" -Level "ERROR"
        return $false
    }

    if ($global:DryRun) {
        Write-Log "DRY-RUN: архiв не створюється: $ArchiveName" -Level "WARNING"
        return $true
    }
    Set-ArchivArchiveElapsedTitle -ArchiveType $ArchiveType -Elapsed ([TimeSpan]::Zero) -SourceSizeText $archiveSourceSizeText
    Write-Log "Створення архiву: $ArchiveName"
    
    $fullArchivePath = Join-Path $ArchivePath $ArchiveName
    
    try {
        $effectiveArcParams = $ArcParams
$archivePassword = Get-ArchivArchivePassword

        if (-not [string]::IsNullOrWhiteSpace($archivePassword)) {
            $effectiveArcParams = "$effectiveArcParams -p`"$archivePassword`""
        }

        $arguments = "$effectiveArcParams `"$fullArchivePath`" `"$SourcePath`""
        
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $ArcPath
        $processInfo.Arguments = $arguments
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $process.Start() | Out-Null
        Add-ProcessToArchivKillOnCloseJob -Process $process

        $archiveSourceSizeBytes = Get-PathSizeBytes -Path $SourcePath
        if ($null -ne $archiveSourceSizeBytes -and $archiveSourceSizeBytes -gt 0) {
            $archiveSourceSizeText = Format-FileSize -Bytes $archiveSourceSizeBytes
        } else {
            $archiveSourceSizeText = ""
        }
        $archiveStartTime = Get-Date
        Set-ArchivArchiveElapsedTitle -ArchiveType $ArchiveType -Elapsed ([TimeSpan]::Zero) -SourceSizeText $archiveSourceSizeText

        while (-not $process.HasExited) {
            $elapsed = (Get-Date) - $archiveStartTime
            Set-ArchivArchiveElapsedTitle -ArchiveType $ArchiveType -Elapsed $elapsed -SourceSizeText $archiveSourceSizeText
            Start-Sleep -Seconds 1
        }

        $standardOutput = $process.StandardOutput.ReadToEnd()
        $errorOutput = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        
        if ($process.ExitCode -eq 0) {
            Set-ArchivArchiveElapsedTitle -ArchiveType $ArchiveType -Elapsed ((Get-Date) - $archiveStartTime) -SourceSizeText $archiveSourceSizeText
            Write-Log "Архiв створено: $fullArchivePath" -Level "SUCCESS"

            $archiveIntegrityEnabled = $false
            $integrityVariable = Get-Variable -Name "enableArchiveIntegrityTest" -Scope Global -ErrorAction SilentlyContinue
            if ($null -eq $integrityVariable) {
                $integrityVariable = Get-Variable -Name "enableArchiveIntegrityTest" -Scope Script -ErrorAction SilentlyContinue
            }
            if ($null -eq $integrityVariable) {
                $integrityVariable = Get-Variable -Name "enableArchiveIntegrityTest" -ErrorAction SilentlyContinue
            }
            if ($null -ne $integrityVariable) {
                $archiveIntegrityEnabled = [bool]$integrityVariable.Value
            }

            if ($archiveIntegrityEnabled) {
                $archivePasswordSwitch = ""
                $passwordSwitchMatch = [regex]::Match($effectiveArcParams, '(^|\s)(-p("[^"]*"|\S+))')
                if ($passwordSwitchMatch.Success) {
                    $archivePasswordSwitch = $passwordSwitchMatch.Groups[2].Value
                }

                if (-not (Test-ArchiveIntegrity -ArchivePath $fullArchivePath -ArcPath $ArcPath -ArchiveType $ArchiveType -ArchivePasswordSwitch $archivePasswordSwitch)) {
                    Write-Log "Архiв створено, але перевiрку цiлiсностi не пройдено: $fullArchivePath" -Level "ERROR"
                    return $false
                }
            } else {
                Write-Log "Перевiрку цiлiсностi архiву вимкнено в налаштуваннях" -Level "WARNING" -LogOnly
            }

            return $true
        } else {
            Write-Log "Помилка архiвацiї (код: $($process.ExitCode)): $fullArchivePath" -Level "ERROR"
            if (-not [string]::IsNullOrWhiteSpace($errorOutput)) {
                Write-Log "7-Zip stderr: $errorOutput" -Level "ERROR"
            }
            if (-not [string]::IsNullOrWhiteSpace($standardOutput)) {
                Write-Log "7-Zip stdout: $standardOutput" -Level "ERROR" -LogOnly
            }
            return $false
        }
    } catch {
        Write-Log "Помилка архiвацiї: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function New-SHA512Hash {
    param(
        [string]$FilePath,
        [string]$HashFilePath
    )
    
    if ($global:DryRun) {
        Write-Log "DRY-RUN: SHA512 хеш не створюється: $(Split-Path $FilePath -Leaf)" -Level "WARNING"
        return $true
    }
    Write-Log "Створення SHA512 хешу: $(Split-Path $FilePath -Leaf)"
    
    if (-not (Test-Path $FilePath)) {
        Write-Log "Файл не знайдено: $FilePath" -Level "ERROR"
        return $false
    }
    
    try {
        # Використовуємо стандартний метод
        $hash = (Get-FileHash -Path $FilePath -Algorithm SHA512).Hash.ToLower()
        $fileName = (Get-Item $FilePath).Name
        
        # Записуємо хеш-файл
        [System.IO.File]::WriteAllText($HashFilePath, "${hash} *${fileName}", [System.Text.Encoding]::UTF8)
        
        Write-Log "Хеш створено: $HashFilePath" -Level "SUCCESS"
        return $true
    } catch {
        Write-Log "Помилка створення хешу: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}


function Test-SHA512Hash {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,

        [Parameter(Mandatory=$true)]
        [string]$HashFilePath,

        [string]$ArchiveType = "ARCHIVE"
    )

    if ($global:DryRun) {
        Write-Log "DRY-RUN: перевiрка SHA512 пропущена: $(Split-Path $FilePath -Leaf)" -Level "WARNING"
        return $true
    }

    if (-not (Test-Path -LiteralPath $FilePath)) {
        Write-Log "Файл для перевiрки SHA512 не знайдено: $FilePath" -Level "ERROR"
        return $false
    }

    if (-not (Test-Path -LiteralPath $HashFilePath)) {
        Write-Log "SHA512 файл не знайдено: $HashFilePath" -Level "ERROR"
        return $false
    }

    try {
        Set-ArchivWindowTitle -Stage "SHA512 test $ArchiveType"

        Write-Log "Перевiрка контрольної суми SHA512: $(Split-Path $FilePath -Leaf)" -Level "INFO"

        $hashLine = (Get-Content -LiteralPath $HashFilePath -Raw).Trim()
        if ([string]::IsNullOrWhiteSpace($hashLine)) {
            Write-Log "SHA512 файл порожнiй: $HashFilePath" -Level "ERROR"
            return $false
        }

        $expectedHash = ($hashLine -split '\s+')[0].Trim().ToLower()
        $actualHash = (Get-FileHash -Path $FilePath -Algorithm SHA512).Hash.ToLower()

        if ($actualHash -eq $expectedHash) {
            Write-Log "Контрольна сума SHA512 збiгається: $(Split-Path $FilePath -Leaf)" -Level "SUCCESS"
            return $true
        }

        Write-Log "Контрольна сума SHA512 НЕ збiгається: $(Split-Path $FilePath -Leaf)" -Level "ERROR"
        Write-Log "Очiкувано: $expectedHash" -Level "ERROR" -LogOnly
        Write-Log "Фактично:  $actualHash" -Level "ERROR" -LogOnly
        return $false
    } catch {
        Write-Log "Помилка перевiрки SHA512: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# =============================================
# ФУНКЦІЇ МЕРЕЖІ ТА SFTP
# =============================================

function Test-SFTPConfig {
    if ([string]::IsNullOrEmpty($Login) -or [string]::IsNullOrEmpty($Password)) {
        Write-Log "SFTP логiн або пароль не встановленi" -Level "ERROR"
        return $false
    }
    
    Write-Log "SFTP конфiгурацiя перевiрена успiшно" -Level "SUCCESS"
    return $true
}

function Test-NetworkConnection {
    try {
        Write-Log "Перевiрка мережевого з'єднання..." -Level "DEBUG" -LogOnly
        
        # Додати -WarningAction SilentlyContinue для приховування виводу
        $connection = Test-NetConnection -ComputerName "google.com" -Port 443 -InformationLevel Quiet -ErrorAction Stop -WarningAction SilentlyContinue
        
        if ($connection) {
            Write-Log "Мережеве з'єднання доступне" -Level "SUCCESS" -LogOnly
            return $true
        } else {
            Write-Log "Мережеве з'єднання недоступне" -Level "ERROR" -LogOnly
            return $false
        }
    } catch {
        Write-Log "Помилка перевiрки мережевого з'єднання: $($_.Exception.Message)" -Level "ERROR" -LogOnly
        return $false
    }
}

function Test-SFTPConnection {
    param(
        [string]$WinSCPPath,
        [string]$RepositorySFTPUrl,
        [string]$HostKey
    )
    
    Write-Log "Перевiрка пiдключення до SFTP сервера: $RepositorySFTPUrl" -Level "DEBUG" -LogOnly
    
    if (-not (Test-Path $WinSCPPath)) {
        Write-Log "WinSCP не знайдено: $WinSCPPath" -Level "ERROR" -LogOnly
        return $false
    }
    
    $testCommand = @"
open $RepositorySFTPUrl -hostkey=$HostKey -timeout=30
ls
exit
"@
    
    $tempScript = [System.IO.Path]::GetTempFileName() + ".txt"
    try {
        $testCommand | Out-File -FilePath $tempScript -Encoding ASCII -Force
        
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $WinSCPPath
        $processInfo.Arguments = "/ini=nul /script=`"$tempScript`""
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $process.Start() | Out-Null
        Add-ProcessToArchivKillOnCloseJob -Process $process
        $output = $process.StandardOutput.ReadToEnd()
        $errorOutput = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        
        if ($process.ExitCode -eq 0) {
            Write-Log "Пiдключення до SFTP сервера успiшне" -Level "SUCCESS" -LogOnly
            return $true
        } else {
            Write-Log "Помилка пiдключення до SFTP сервера (код: $($process.ExitCode))" -Level "ERROR" -LogOnly
            return $false
        }

    } finally {
        if (Test-Path $tempScript) {
            Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
        }
    }
}

function Send-FileViaWinSCP {
    param(
        [string]$WinSCPPath,
        [string]$RepositorySFTPUrl,
        [string]$HostKey,
        [string]$LocalFilePath,
        [string]$RemoteDirectory
    )
    
    Write-Log "Завантаження через WinSCP: $(Split-Path $LocalFilePath -Leaf) -> $RemoteDirectory"
    
    if (-not (Test-Path $LocalFilePath)) {
        Write-Log "Файл не знайдено: $LocalFilePath" -Level "ERROR"
        return $false
    }
    
    if (-not (Test-Path $WinSCPPath)) {
        Write-Log "WinSCP не знайдено: $WinSCPPath" -Level "ERROR"
        return $false
    }
    
    # Створюємо тимчасовий скрипт для WinSCP
    $winscpCommand = @"
open $RepositorySFTPUrl -hostkey=$HostKey
cd /$RemoteDirectory
put "$LocalFilePath"
exit
"@
    
    $tempScript = [System.IO.Path]::GetTempFileName() + ".txt"
    try {
        $winscpCommand | Out-File -FilePath $tempScript -Encoding ASCII -Force
        
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $WinSCPPath
        $processInfo.Arguments = "/ini=nul /script=`"$tempScript`""
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $process.Start() | Out-Null
        Add-ProcessToArchivKillOnCloseJob -Process $process
        $output = $process.StandardOutput.ReadToEnd()
        $errorOutput = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        
        if ($process.ExitCode -eq 0) {
            Write-Log "Файл успiшно завантажено: $(Split-Path $LocalFilePath -Leaf)" -Level "SUCCESS"
            return $true
        } else {
            Write-Log "Помилка завантаження (код: $($process.ExitCode)): $(Split-Path $LocalFilePath -Leaf)" -Level "ERROR"
            return $false
        }
    } catch {
        Write-Log "Помилка пiд час завантаження через WinSCP: $($_.Exception.Message)" -Level "ERROR"
        return $false
    } finally {
        # Очищаємо тимчасовий файл
        if (Test-Path $tempScript) {
            Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
        }
    }
}

# =============================================
# ФУНКЦІЇ ДЛЯ РОБОТИ З МЕРЕЖЕВОЮ ПАПКОЮ
# =============================================

function Connect-NetworkDrive {
    Write-Log "Пiдключення мережевого диска..." -Level "INFO"
    
    $driveLetter = "Z:"
    $networkPath = $networkCopyConfig.NetworkPath.TrimEnd('\')
    $username = $networkCopyConfig.Username
    $password = Get-ArchivNetworkPassword

    if ([string]::IsNullOrWhiteSpace($username) -or [string]::IsNullOrWhiteSpace($password)) {
        Write-Log "Логiн або пароль мережевої папки не встановлено / не знайдено в Windows Credential Manager" -Level "ERROR"
        return $false
    }
    
    # Перевіряємо, чи не підключений вже диск
    try {
        $existingDrive = Get-PSDrive -Name $driveLetter.TrimEnd(':') -ErrorAction SilentlyContinue
        if ($existingDrive) {
            Write-Log "Диск $driveLetter вже пiдключений. Спробуємо використати існуючий." -Level "INFO"
            
            # Перевіряємо, чи працює диск
            if (Test-Path $driveLetter) {
                Write-Log "Диск $driveLetter працює нормально" -Level "SUCCESS"
                return $true
            } else {
                Write-Log "Диск $driveLetter не працює, намагаємося вiдключити..." -Level "WARNING"
                net use $driveLetter /delete /y 2>$null | Out-Null
                Start-Sleep -Seconds 2
            }
        }
    } catch {
        Write-Log "Помилка перевiрки диска: $($_.Exception.Message)" -Level "WARNING" -LogOnly
    }
    
    # Підключаємо диск
    $cmd = "net use $driveLetter `"$networkPath`" /user:`"$username`" `"$password`" /persistent:no"
    
    # Виконуємо команду
    $output = cmd /c $cmd 2>&1
    $exitCode = $LASTEXITCODE
    
    if ($exitCode -eq 0) {
        # Даємо системі час на ініціалізацію диска
        Start-Sleep -Seconds 3
        
        # Перевіряємо доступ
        if (Test-Path $driveLetter) {
            Write-Log "Мережевий диск пiдключено успiшно" -Level "SUCCESS"
            
            # Отримуємо інформацію про диск
            try {
                $driveInfo = Get-PSDrive -Name $driveLetter.TrimEnd(':') -ErrorAction Stop
                $freeSpaceGB = [math]::Round($driveInfo.Free / 1GB, 2)
                Write-Log "Доступний вiльний простiр: $freeSpaceGB GB" -Level "INFO"
                
                # Перевірка достатності місця
                if ($freeSpaceGB -gt 10) {
                    Write-Log "Вiльного простору достатньо." -Level "SUCCESS"
                } else {
                    Write-Log "Увага! Мало вiльного мiсця: $freeSpaceGB GB" -Level "WARNING"
                }
            } catch {
                Write-Log "Не вдалося отримати iнформацiю про диск" -Level "WARNING" -LogOnly
            }
            
            return $true
        } else {
            Write-Log "Диск пiдключено, але доступ вiдсутнiй" -Level "ERROR"
            return $false
        }
    } else {
        Write-Log "Помилка пiдключення мережевого диска (код: $exitCode)" -Level "ERROR"
        return $false
    }
}

function Disconnect-NetworkDrive {
    $driveLetter = "Z:"
    
    Write-Log "Вiдключення мережевого диска $driveLetter..." -Level "DEBUG" -LogOnly
    
    net use $driveLetter /delete /y 2>$null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Мережевий диск вiдключено" -Level "SUCCESS" -LogOnly
        return $true
    } else {
        Write-Log "Помилка вiдключення мережевого диска" -Level "WARNING" -LogOnly
        return $false
    }
}

function Copy-ToNetworkDrive {
    param(
        [string]$SourcePath,
        [string]$DestinationFolder
    )
    
    $fileName = Split-Path $SourcePath -Leaf
    $driveLetter = "Z:"
    $networkPath = "$driveLetter\$DestinationFolder"
    
    Write-Log "Копiювання до мережевого диска: $fileName -> $networkPath"
        
    # Перевіряємо, чи диск підключено
    if (-not (Test-Path $driveLetter)) {
        Write-Log "Мережевий диск $driveLetter не пiдключено" -Level "ERROR"
        return $false
    }
    
    # Створюємо цільовий каталог, якщо не існує
    if (-not (Test-Path $networkPath)) {
        try {
            New-Item -ItemType Directory -Path $networkPath -Force | Out-Null
            Write-Log "Створено каталог: $networkPath" -Level "SUCCESS"
        } catch {
            Write-Log "Помилка створення каталогу: $($_.Exception.Message)" -Level "ERROR"
            return $false
        }
    }
    
    $destFile = Join-Path $networkPath $fileName
    
    try {
        # Копіюємо файл
        Copy-Item -Path $SourcePath -Destination $destFile -Force -ErrorAction Stop
        
        # Перевіряємо успішність
        if (Test-Path $destFile) {
            $fileSize = (Get-Item $destFile).Length / 1MB
            Write-Log "Файл успiшно скопiйовано: $fileName ($([math]::Round($fileSize, 2)) MB)" -Level "SUCCESS"
            return $true
        } else {
            Write-Log "Файл не знайдено пiсля копiювання" -Level "ERROR"
            return $false
        }
        
    } catch {
        Write-Log "Помилка копiювання: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Process-NetworkCopy {
    param(
        [hashtable]$Results
    )
    
    if (-not $enableNetworkCopy) {
        Write-Log "Копiювання в мережеву папку вимкнено в налаштуваннях" -Level "INFO"
        return
    }
    
    Write-Log "=== КОПIЮВАННЯ В МЕРЕЖЕВУ ПАПКУ ==="
    Write-Log "--- ПIДКЛЮЧЕННЯ МЕРЕЖЕВОГО ДИСКА ---"
    
    # Підключаємо мережевий диск
    $connected = Connect-NetworkDrive
    
    if (-not $connected) {
        Write-Log "Не вдалося пiдключити мережевий диск - пропускаємо копiювання" -Level "ERROR"
        return
    }
    
    $copySuccess = 0
    $copyTotal = 0
    
    # Копіюємо архіви та хеш-файли
    foreach ($archiveType in $Results.Keys) {
        if ($Results[$archiveType].ArchiveSuccess -and $Results[$archiveType].HashSuccess) {
            $copyTotal += 2
            
            # Визначаємо папку призначення
            $targetFolder = if ($archiveType -eq "BLOG") { "BLOG" } else { "Model" }
            
            # Копіюємо архів
            Write-Log "--- КОПIЮВАННЯ В МЕРЕЖЕВУ ПАПКУ АРХІВУ $archiveType ---"
            $archiveCopy = Copy-ToNetworkDrive -SourcePath $Results[$archiveType].ArchivePath -DestinationFolder $targetFolder
            if ($archiveCopy) { $copySuccess++ }
            
            # Копіюємо хеш-файл
            Write-Log "--- КОПIЮВАННЯ В МЕРЕЖЕВУ ПАПКУ ХЕШУ АРХІВУ $archiveType ---"
            $hashCopy = Copy-ToNetworkDrive -SourcePath $Results[$archiveType].HashPath -DestinationFolder $targetFolder
            if ($hashCopy) { $copySuccess++ }
            
            if ($archiveCopy -and $hashCopy) {
                Write-Log "Успiшно скопiйовано $archiveType в мережеву папку" -Level "SUCCESS" -LogOnly
            }
        }
    }
    
    Write-Log "=== ПІДСУМОК КОПIЮВАННЯ В МЕРЕЖЕВУ ПАПКУ ==="
    
    if ($copyTotal -gt 0) {
        $percentage = [math]::Round(($copySuccess / $copyTotal) * 100, 1)
        Write-Log "Скопiйовано $copySuccess з $copyTotal файлiв ($percentage%) в мережеву папку" -Level "SUCCESS"
    } else {
        Write-Log "Немає файлiв для копiювання в мережеву папку" -Level "WARNING"
    }
    
    # Відключаємо диск
    Disconnect-NetworkDrive | Out-Null
}

# =============================================
# >>> WINDOW TITLE STAGES PATCH: BEGIN
# >>> ARCHIVE WINDOW TITLE PROGRESS PATCH: BEGIN
# >>> ARCHIVE ELAPSED WINDOW TITLE PATCH: BEGIN
function Set-ArchivArchiveElapsedTitle {
    param(
        [string]$ArchiveType,
        [TimeSpan]$Elapsed,
        [string]$SourceSizeText = ""
    )

    try {
        if ([string]::IsNullOrWhiteSpace($ArchiveType)) {
            $ArchiveType = "ARCHIVE"
        }

                $elapsedText = $Elapsed.ToString('hh\:mm\:ss')

        if ([string]::IsNullOrWhiteSpace($SourceSizeText)) {
            $Host.UI.RawUI.WindowTitle = "ARCHIV | $ArchiveType | $elapsedText"
        } else {
            $Host.UI.RawUI.WindowTitle = "ARCHIV | $ArchiveType | $elapsedText | $SourceSizeText"
        }
    } catch {
        # Window title is best-effort only.
    }
}
# <<< ARCHIVE ELAPSED WINDOW TITLE PATCH: END
function Set-ArchivArchiveProgressTitle {
    param(
        [string]$ArchiveName,
        [string]$ArchiveType,
        [int]$Percent
    )

    try {
        $safePercent = [Math]::Max(0, [Math]::Min(100, $Percent))

        if ([string]::IsNullOrWhiteSpace($ArchiveType)) {
            $ArchiveType = "ARCHIVE"
        }

        $Host.UI.RawUI.WindowTitle = "ARCHIV | $ArchiveType | $safePercent%"
    } catch {
        # Window title is best-effort only.
    }
}
# <<< ARCHIVE WINDOW TITLE PROGRESS PATCH: END
function Set-ArchivWindowTitle {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Stage
    )

    try {
        $Host.UI.RawUI.WindowTitle = "ARCHIV | $Stage"
    } catch {
        # Window title is best-effort only.
    }
}
# <<< WINDOW TITLE STAGES PATCH: END
# ОСНОВНА ЛОГІКА
# =============================================

# >>> HISTORY / STATS / HEALTH PATCH: BEGIN
function Show-ArchivRunStatistics {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Results,

        [Parameter(Mandatory=$true)]
        [array]$Archives
    )

    try {
        Write-Log "=== СТАТИСТИКА АРХIВАЦIЇ ==="

        foreach ($archive in $Archives) {
            $type = [string]$archive.Type
            $archivePath = Join-Path $archive.Destination $archive.Name
            $hashPath = "$archivePath.sha512"

            $sourceSizeBytes = Get-PathSizeBytes -Path $archive.Source
            $archiveSizeBytes = Get-ArchivFileSizeSafe -Path $archivePath
            $compressionRatio = Get-ArchivCompressionRatio -SourceSizeBytes $sourceSizeBytes -ArchiveSizeBytes $archiveSizeBytes

            Write-Log "${type}:" -NoTimestamp
            Write-Log "  Джерело: $(if ($null -ne $sourceSizeBytes) { Format-FileSize -Bytes $sourceSizeBytes } else { 'невідомо' })" -NoTimestamp

            if ($global:DryRun) {
                Write-Log "  Архiв: DRY-RUN, фактично не створювався" -NoTimestamp
                Write-Log "  Стиснення: DRY-RUN" -NoTimestamp
            } else {
                Write-Log "  Архiв: $(if ($null -ne $archiveSizeBytes) { Format-FileSize -Bytes $archiveSizeBytes } else { 'не створено' })" -NoTimestamp
                Write-Log "  Стиснення: $(if ($null -ne $compressionRatio) { "$compressionRatio%" } else { 'невідомо' })" -NoTimestamp
            }

            Write-Log "  SHA512: $(if (Test-Path -LiteralPath $hashPath) { 'створено' } elseif ($global:DryRun) { 'DRY-RUN' } else { 'не створено' })" -NoTimestamp
        }

        Write-Log "==="
    } catch {
        Write-Log "Помилка формування статистики архiвацiї: $($_.Exception.Message)" -Level "WARNING"
    }
}

function Update-ArchivHistory {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ReportPath,

        [string]$HistoryPath = ""
    )

    try {
        if ([string]::IsNullOrWhiteSpace($HistoryPath)) {
            $HistoryPath = Join-Path $logPath "history.json"
        }

        if (-not (Test-Path -LiteralPath $ReportPath)) {
            Write-Log "JSON-звiт не знайдено для оновлення history.json: $ReportPath" -Level "WARNING"
            return $false
        }

        $report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json

        $history = @()
        if (Test-Path -LiteralPath $HistoryPath) {
            try {
                $existing = Get-Content -LiteralPath $HistoryPath -Raw | ConvertFrom-Json
                if ($existing -is [array]) {
                    $history = @($existing)
                } elseif ($null -ne $existing) {
                    $history = @($existing)
                }
            } catch {
                Write-Log "history.json пошкоджений або має некоректний формат. Буде створено новий файл." -Level "WARNING"
                $history = @()
            }
        }

        $archivesCount = 0
        $archivesSuccess = 0
        $totalSourceBytes = [int64]0
        $totalArchiveBytes = [int64]0

        foreach ($archive in @($report.archives)) {
            $archivesCount++

            if ($archive.archive_success -and $archive.hash_success) {
                $archivesSuccess++
            }

            if ($null -ne $archive.source_size_bytes) {
                $totalSourceBytes += [int64]$archive.source_size_bytes
            }

            if ($null -ne $archive.archive_size_bytes) {
                $totalArchiveBytes += [int64]$archive.archive_size_bytes
            }
        }

        $overallSuccess = ($archivesCount -gt 0 -and $archivesSuccess -eq $archivesCount)

        if ($report.dry_run) {
            $overallSuccess = $true
        }

        $entry = [PSCustomObject]@{
            started_at               = $report.started_at
            finished_at              = $report.finished_at
            duration_seconds         = $report.duration_seconds
            duration_text            = $report.duration_text
            dry_run                  = [bool]$report.dry_run
            success                  = [bool]$overallSuccess
            archives_count           = $archivesCount
            archives_success         = $archivesSuccess
            total_source_size_bytes  = $totalSourceBytes
            total_source_size_text   = Format-FileSize -Bytes $totalSourceBytes
            total_archive_size_bytes = if ($totalArchiveBytes -gt 0) { $totalArchiveBytes } else { $null }
            total_archive_size_text  = if ($totalArchiveBytes -gt 0) { Format-FileSize -Bytes $totalArchiveBytes } else { $null }
            report_file              = $ReportPath
            log_file                 = $report.log_file
        }

        $history = @($history + $entry) |
            Sort-Object started_at -Descending |
            Select-Object -First 100

        $historyJson = $history | ConvertTo-Json -Depth 8
        [System.IO.File]::WriteAllText($HistoryPath, $historyJson, [System.Text.Encoding]::UTF8)

        Write-Log "Iсторiю запускiв оновлено: $HistoryPath" -Level "SUCCESS"
        return $true
    } catch {
        Write-Log "Помилка оновлення history.json: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function ConvertTo-ArchivBool {
    param($Value)

    if ($null -eq $Value) {
        return $false
    }

    if ($Value -is [array]) {
        if ($Value.Count -eq 0) {
            return $false
        }
        $Value = $Value[0]
    }

    if ($Value -is [bool]) {
        return $Value
    }

    $text = ([string]$Value).Trim()
    return ($text -match '^(true|1|yes|y|так)$')
}
function Format-ArchivAgeText {
    param([TimeSpan]$Age)

    if ($Age.TotalMinutes -lt 1) {
        return "щойно"
    }

    if ($Age.TotalHours -lt 1) {
        $minutes = [math]::Max(1, [int][math]::Round($Age.TotalMinutes))
        return "$minutes хв тому"
    }

    if ($Age.TotalDays -lt 1) {
        $hours = [int][math]::Floor($Age.TotalHours)
        $minutes = [int]($Age.Minutes)

        if ($minutes -gt 0) {
            return "$hours год $minutes хв тому"
        }

        return "$hours год тому"
    }

    $days = [int][math]::Floor($Age.TotalDays)
    return "$days дн. тому"
}

function Get-ArchivCompressionSavedPercent {
    param(
        [Nullable[Int64]]$SourceBytes,
        [Nullable[Int64]]$ArchiveBytes
    )

    if ($null -eq $SourceBytes -or $null -eq $ArchiveBytes -or $SourceBytes -le 0) {
        return $null
    }

    return [math]::Round((1 - ($ArchiveBytes / $SourceBytes)) * 100, 1)
}
function Test-ArchivBackupHealth {
    param(
        [string]$HistoryPath = "",
        [int]$WarningDays = 3,
        [int]$CriticalDays = 7
    )

    try {
        if ([string]::IsNullOrWhiteSpace($HistoryPath)) {
            $HistoryPath = Join-Path $logPath "history.json"
        }

        Write-Log "=== СТАН РЕЗЕРВНИХ КОПIЙ ==="

        if (-not (Test-Path -LiteralPath $HistoryPath)) {
            Write-Log "history.json ще не створено. Стан резервних копiй буде доступний пiсля першого запуску." -Level "WARNING"
            Write-Log "==="
            return
        }

        $historyRaw = Get-Content -LiteralPath $HistoryPath -Raw
        if ([string]::IsNullOrWhiteSpace($historyRaw)) {
            Write-Log "history.json порожнiй" -Level "WARNING"
            Write-Log "==="
            return
        }

        $historyParsed = $historyRaw | ConvertFrom-Json
        $history = @()
        foreach ($item in @($historyParsed)) {
            if ($item -is [array]) { $history += @($item) } else { $history += $item }
        }

        $successfulRealRuns = @($history | Where-Object {
            ((ConvertTo-ArchivBool $_.success) -eq $true) -and ((ConvertTo-ArchivBool $_.dry_run) -ne $true)
        } | Sort-Object started_at -Descending)

        $lastAnyRun = $history | Sort-Object started_at -Descending | Select-Object -First 1

        if ($null -ne $lastAnyRun) {
            $lastAnyRunIsDryRun = ConvertTo-ArchivBool $lastAnyRun.dry_run
            Write-Log "Останнiй запуск: $($lastAnyRun.started_at)$(if ($lastAnyRunIsDryRun) { ' (DRY-RUN)' } else { '' })" -NoTimestamp
        }

        if ($successfulRealRuns.Count -eq 0) {
            Write-Log "У history.json немає успiшних реальних запускiв архiвацiї" -Level "WARNING"
            Write-Log "==="
            return
        }

        $lastSuccess = $successfulRealRuns | Select-Object -First 1
        $lastSuccessDate = [datetime]::Parse($lastSuccess.started_at)
        $age = (Get-Date) - $lastSuccessDate
        $ageText = Format-ArchivAgeText -Age $age
        $lastSuccessText = $lastSuccessDate.ToString("yyyy-MM-dd HH:mm:ss")

        Write-Log "Останнiй успiшний архiв: $lastSuccessText ($ageText)" -NoTimestamp
        Write-Log "Архiвiв у запуску: $($lastSuccess.archives_success) з $($lastSuccess.archives_count)" -NoTimestamp

        if ($lastSuccess.total_source_size_text -and $lastSuccess.total_archive_size_text) {
            $savedPercent = Get-ArchivCompressionSavedPercent `
                -SourceBytes ([int64]$lastSuccess.total_source_size_bytes) `
                -ArchiveBytes ([int64]$lastSuccess.total_archive_size_bytes)

            if ($null -ne $savedPercent) {
                Write-Log "Стиснення: $($lastSuccess.total_source_size_text) -> $($lastSuccess.total_archive_size_text) ($savedPercent%)" -NoTimestamp
            } else {
                Write-Log "Загальний розмiр джерел: $($lastSuccess.total_source_size_text)" -NoTimestamp
                Write-Log "Загальний розмiр архiвiв: $($lastSuccess.total_archive_size_text)" -NoTimestamp
            }
        } else {
            Write-Log "Загальний розмiр джерел: $($lastSuccess.total_source_size_text)" -NoTimestamp
            if ($lastSuccess.total_archive_size_text) {
                Write-Log "Загальний розмiр архiвiв: $($lastSuccess.total_archive_size_text)" -NoTimestamp
            }
        }

        if ($age.TotalDays -ge $CriticalDays) {
            Write-Log "КРИТИЧНО: останнiй успiшний архiв старший за $CriticalDays дн." -Level "ERROR"
        } elseif ($age.TotalDays -ge $WarningDays) {
            Write-Log "УВАГА: останнiй успiшний архiв старший за $WarningDays дн." -Level "WARNING"
        } else {
            Write-Log "Стан резервних копiй: OK" -Level "SUCCESS"
        }

        Write-Log "==="
    } catch {
        Write-Log "Помилка перевiрки стану резервних копiй: $($_.Exception.Message)" -Level "WARNING"
    }
}
# <<< HISTORY / STATS / HEALTH PATCH: END
# >>> JSON REPORT PATCH: BEGIN
function Get-ArchivFileSizeSafe {
    param([string]$Path)

    try {
        if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path)) {
            return [int64](Get-Item -LiteralPath $Path -ErrorAction Stop).Length
        }
    } catch {
    }

    return $null
}

function Get-ArchivCompressionRatio {
    param(
        [Nullable[Int64]]$SourceSizeBytes,
        [Nullable[Int64]]$ArchiveSizeBytes
    )

    if ($null -eq $SourceSizeBytes -or $null -eq $ArchiveSizeBytes) {
        return $null
    }

    if ($SourceSizeBytes -le 0) {
        return $null
    }

    return [math]::Round(($ArchiveSizeBytes / $SourceSizeBytes) * 100, 2)
}

function New-ArchivJsonReport {
    param(
        [Parameter(Mandatory=$true)]
        [datetime]$StartedAt,

        [Parameter(Mandatory=$true)]
        [datetime]$FinishedAt,

        [Parameter(Mandatory=$true)]
        [hashtable]$Results,

        [Parameter(Mandatory=$true)]
        [array]$Archives,

        [string]$ReportPath
    )

    try {
        if ([string]::IsNullOrWhiteSpace($ReportPath)) {
            $ReportPath = [System.IO.Path]::ChangeExtension($global:logFile, ".json")
        }

        $duration = $FinishedAt - $StartedAt
        $archiveReports = @()

        foreach ($archive in $Archives) {
            $type = [string]$archive.Type
            $archivePath = Join-Path $archive.Destination $archive.Name
            $hashPath = "$archivePath.sha512"

            $result = $null
            if ($Results -and $Results.ContainsKey($type)) {
                $result = $Results[$type]
            }

            $sourceSizeBytes = Get-PathSizeBytes -Path $archive.Source
            $archiveSizeBytes = Get-ArchivFileSizeSafe -Path $archivePath
            $hashSizeBytes = Get-ArchivFileSizeSafe -Path $hashPath

            $archiveSuccess = $false
            $hashSuccess = $false

            if ($result) {
                $archiveSuccess = [bool]$result.ArchiveSuccess
                $hashSuccess = [bool]$result.HashSuccess
            }

            $archiveReports += [PSCustomObject]@{
                type                    = $type
                source_path             = $archive.Source
                source_size_bytes       = $sourceSizeBytes
                source_size_text        = if ($null -ne $sourceSizeBytes) { Format-FileSize -Bytes $sourceSizeBytes } else { $null }
                archive_name            = $archive.Name
                archive_path            = $archivePath
                archive_size_bytes      = $archiveSizeBytes
                archive_size_text       = if ($null -ne $archiveSizeBytes) { Format-FileSize -Bytes $archiveSizeBytes } else { $null }
                hash_path               = $hashPath
                hash_size_bytes         = $hashSizeBytes
                compression_ratio_pct   = Get-ArchivCompressionRatio -SourceSizeBytes $sourceSizeBytes -ArchiveSizeBytes $archiveSizeBytes
                archive_success         = $archiveSuccess
                hash_success            = $hashSuccess
                hash_verify_success     = if ($result) { [bool]$result.HashVerifySuccess } else { $false }
            }
        }

        $sftpStatus = if ($enableSFTPUpload) {
            if ($global:DryRun) { "dry_run_skipped" } else { "enabled" }
        } else {
            "disabled"
        }

        $networkStatus = if ($enableNetworkCopy) {
            if ($global:DryRun) { "dry_run_skipped" } else { "enabled" }
        } else {
            "disabled"
        }

        $report = [PSCustomObject]@{
            script_name              = "ARCHIV_VETOFFICE"
            script_version           = $ScriptVersion
            script_date              = $ScriptDate
            hostname                 = $env:COMPUTERNAME
            username                 = $env:USERNAME
            started_at               = $StartedAt.ToString("yyyy-MM-ddTHH:mm:ss")
            finished_at              = $FinishedAt.ToString("yyyy-MM-ddTHH:mm:ss")
            duration_seconds         = [math]::Round($duration.TotalSeconds, 3)
            duration_text            = $duration.ToString("hh\:mm\:ss")
            dry_run                  = [bool]$global:DryRun
            root_path                = $rootPath
            config_path              = $configPath
            log_file                 = $global:logFile
            report_file              = $ReportPath
            archive_prefix           = $archivePrefix
            archive_params           = if ($safeArchiveParams) { $safeArchiveParams } else { $archiveParams }
            archive_integrity_test_enabled = [bool]$enableArchiveIntegrityTest
            archive_retention_enabled = [bool]$enableArchiveDeletion
            archive_retention_keep_count = [int](Get-ArchivConfigValue -Name "archiveRetentionKeepCount" -DefaultValue $archiveVersions)
            archive_retention_keep_days = [int](Get-ArchivConfigValue -Name "archiveRetentionKeepDays" -DefaultValue 0)
            free_space_reserve_gb    = $freeSpaceReserveGB
            archive_space_multiplier = $archiveSpaceMultiplier
            archives                 = $archiveReports
            sftp                     = [PSCustomObject]@{
                enabled = [bool]$enableSFTPUpload
                status  = $sftpStatus
            }
            network_copy             = [PSCustomObject]@{
                enabled = [bool]$enableNetworkCopy
                status  = $networkStatus
            }
            baza_sync                = [PSCustomObject]@{
                local_enabled   = -not [bool]$excludeComponents.BAZA
                network_enabled = (-not [bool]$excludeComponents.BAZA_Network) -and [bool]$enableNetworkCopy
            }
        }

        $reportDir = Split-Path -Parent $ReportPath
        if (-not (Test-Path -LiteralPath $reportDir)) {
            New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
        }

        $json = $report | ConvertTo-Json -Depth 8
        [System.IO.File]::WriteAllText($ReportPath, $json, [System.Text.Encoding]::UTF8)

        Write-Log "JSON-звiт створено: $ReportPath" -Level "SUCCESS"
        return $true
    } catch {
        Write-Log "Помилка створення JSON-звiту: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}
# <<< JSON REPORT PATCH: END
function Main {
    Set-ArchivWindowTitle -Stage "Запуск скрипта"
    # Ініціалізація
    $scriptStartTime = Get-Date
    $now = Get-Date -Format "yyyyMMdd_HHmm"
    $global:logFile = "$logPath\ARCHIV_VETOFFICE_$now.log"
    $global:jsonReportFile = "$logPath\ARCHIV_VETOFFICE_$now.json"
    
    Write-Log "==="
    Write-Log "=== ПОЧАТОК РОБОТИ СКРИПТА ARCHIV_VETOFFICE v.$ScriptVersion ==="
    Write-Log "Файл конфiгурацiї: $configPath" -Level "INFO"
    Write-Log "==="
    
    $safeArchiveParams = $archiveParams
    if (-not [string]::IsNullOrWhiteSpace($safeArchiveParams)) {
        $safeArchiveParams = [regex]::Replace($safeArchiveParams, '-p("[^"]*"|\S+)', '-p*****')
    }
    Write-Log "=== ОПЦIЇ СКРИПТА ==="
    Write-Log "Версiя та дата скрипта: $ScriptVersion вiд $ScriptDate" -NoTimestamp
    Write-Log "Час початку: $($scriptStartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -NoTimestamp
    Write-Log "Кореневий каталог: $rootPath" -NoTimestamp
    Write-Log "Режим логування: $LogLevel" -NoTimestamp
    Write-Log "JSON-звiт: $global:jsonReportFile" -NoTimestamp
    Write-Log "Iсторiя запускiв: $(Join-Path $logPath 'history.json')" -NoTimestamp
    Write-Log "DRY-RUN: $(if ($global:DryRun) {'УВIМКНЕНО'} else {'ВИМКНЕНО'})" -NoTimestamp
    Write-Log "Параметри для 7-Zip: $safeArchiveParams" -NoTimestamp
    Write-Log "Перевiрка архiвiв 7-Zip: $(if ($enableArchiveIntegrityTest) {'УВIМКНЕНО'} else {'ВИМКНЕНО'})" -NoTimestamp
    if ($enableNetworkCopy) { Write-Log "Копiювання в мережу: УВIМКНЕНО" -NoTimestamp } else { Write-Log "Копiювання в мережу: ВИМКНЕНО" -Level "DEBUG" -LogOnly }
    if (-not $excludeComponents.BAZA_Network) { Write-Log "Синхронiзацiя BAZA в мережу: УВIМКНЕНО" -NoTimestamp } else { Write-Log "Синхронiзацiя BAZA в мережу: ВИМКНЕНО" -Level "DEBUG" -LogOnly }
    if (-not $excludeComponents.BAZA) { Write-Log "Синхронiзацiя BAZA локальна: УВIМКНЕНО" -NoTimestamp } else { Write-Log "Синхронiзацiя BAZA локальна: ВИМКНЕНО" -Level "DEBUG" -LogOnly }
    Write-Log "==="
    
    # ОЧИЩЕННЯ СТАРИХ ЛОГІВ - виконується в кінці
    
    # Перевірка шляхів
    Set-ArchivWindowTitle -Stage "Перевiрка шляхiв"
    Write-Log "=== ПЕРЕВIРКА НЕОБХIДНИХ ШЛЯХIВ ==="

    $requiredPaths = @(
        @{Path=$arcPath; Description="7-Zip"},
        @{Path=$winSCPPath; Description="WinSCP"},
        @{Path=$logPath; Description="Каталог логiв"},
        @{Path=$bazaPaths.Source; Description="Каталог BAZA"},
        @{Path=$bazaPaths.Destination_Local; Description="Локальний каталог архiву BAZA"}
    )
    
    # Додаємо шляхи тільки для невимкнених компонентів
    if (-not $excludeComponents.Blog) {
        $requiredPaths += @{Path=(Split-Path $sourcePaths.Blog -Parent); Description="Каталог BLOG"}
        $requiredPaths += @{Path=$archiveDirs.Blog; Description="Каталог архiву BLOG"}
    }
    
    if (-not $excludeComponents.VETOFFICE) {
        $requiredPaths += @{Path=(Split-Path $sourcePaths.Model -Parent); Description="Каталог VETOFFICE"}
        $requiredPaths += @{Path=$archiveDirs.Model; Description="Каталог архiву VETOFFICE"}
    }
    
    $allPathsExist = $true
    foreach ($item in $requiredPaths) {
        if (-not (Test-PathWithLog $item.Path $item.Description)) {
            $allPathsExist = $false
        }
    }

    # Показуємо підсумок перевірки шляхів
    Show-PathCheckSummary -CheckedPaths $requiredPaths -AllPathsExist $allPathsExist

    if (-not $allPathsExist) {
        Write-Log "Критична помилка: не знайдено обов'язковi шляхи" -Level "ERROR"
        return
    }
    
    # Створення архівів (тільки для невимкнених компонентів)
    $archives = @()
    
    if (-not $excludeComponents.VETOFFICE) {
        $archives += @{
            Name = "$($archivePrefix)_$now.mdz"
            Source = $sourcePaths.Model
            Destination = $archiveDirs.Model
            Type = "VETOFFICE"
        }
    }
    
    if (-not $excludeComponents.Blog) {
        $archives += @{
            Name = "$($archivePrefix)_blog_$now.mdz"
            Source = $sourcePaths.Blog
            Destination = $archiveDirs.Blog
            Type = "BLOG"
        }
    }
    
    $results = @{}
    
    Write-Log "=== АРХIВАЦIЯ ТА СТВОРЕННЯ ХЕШУ ==="
    $effectiveFreeSpaceReserveGB = if ($null -ne $freeSpaceReserveGB -and "$freeSpaceReserveGB" -ne "") { $freeSpaceReserveGB } elseif ($null -ne $archiveMinFreeSpaceGB -and "$archiveMinFreeSpaceGB" -ne "") { $archiveMinFreeSpaceGB } else { 0 }
    Write-Log "Параметри перевiрки мiсця: резерв=$effectiveFreeSpaceReserveGB GB; множник=$archiveSpaceMultiplier" -Level "INFO"
    foreach ($archive in $archives) {
        Set-ArchivWindowTitle -Stage "Архiвацiя $($archive.Type)"
        Write-Log "" -NoTimestamp
        Write-Log "--- АРХIВАЦIЯ $($archive.Type) ---"

        $success = New-Archive `
            -SourcePath $archive.Source `
            -ArchivePath $archive.Destination `
            -ArchiveName $archive.Name `
            -ArcPath $arcPath `
            -ArcParams $archiveParams `
            -ReserveMultiplier $archiveSpaceMultiplier `
            -MinFreeSpaceGB $freeSpaceReserveGB `
            -ArchiveType $archive.Type
        
        if ($success) {
            Set-ArchivWindowTitle -Stage "SHA512 $($archive.Type)"
            Write-Log "" -NoTimestamp
            Write-Log "--- СТВОРЕННЯ ХЕШУ $($archive.Type) ---"
            $archivePath = Join-Path $archive.Destination $archive.Name
            $hashPath = "$archivePath.sha512"
            $hashSuccess = New-SHA512Hash -FilePath $archivePath -HashFilePath $hashPath
            $hashVerifySuccess = $false
            if ($hashSuccess) {
                Set-ArchivWindowTitle -Stage "SHA512 test $($archive.Type)"
                Write-Log "" -NoTimestamp
                Write-Log "--- ПЕРЕВIРКА SHA512 $($archive.Type) ---"
                $hashVerifySuccess = Test-SHA512Hash -FilePath $archivePath -HashFilePath $hashPath -ArchiveType $archive.Type
            }
            
            $results[$archive.Type] = @{
                ArchivePath = $archivePath
                HashPath = $hashPath
                ArchiveSuccess = $success
                HashSuccess = ($hashSuccess -and $hashVerifySuccess)
                HashCreated = $hashSuccess
                HashVerifySuccess = $hashVerifySuccess
            }
        } else {
            $results[$archive.Type] = @{
                ArchiveSuccess = $false
                HashSuccess = $false
                HashCreated = $false
                HashVerifySuccess = $false
            }
        }
    }
    
    Write-Log "==="
    
    if ($global:DryRun -and $enableSFTPUpload) {
        Write-Log "=== ЗАВАНТАЖЕННЯ НА SFTP ==="
        Write-Log "DRY-RUN: завантаження на SFTP пропущено" -Level "WARNING"
        Write-Log "==="
    }
    # Завантаження на SFTP
    Set-ArchivWindowTitle -Stage "SFTP"
    if ($enableSFTPUpload -and -not $global:DryRun) {
        Write-Log "=== ЗАВАНТАЖЕННЯ НА SFTP ==="
        Write-Log "--- ПЕРЕВІРКА КОНФІГУРАЦІЇ SFTP ---"
        
        # Перевірка конфігурації SFTP
        if (-not (Test-SFTPConfig)) {
            Write-Log "SFTP конфiгурацiя невiрна - пропускаємо завантаження" -Level "ERROR"
        } elseif (-not (Test-NetworkConnection)) {
            Write-Log "Мережеве з'єднання недоступне - пропускаємо завантаження" -Level "ERROR"
        } elseif (-not (Test-SFTPConnection -WinSCPPath $winSCPPath -RepositorySFTPUrl $sftpUrl -HostKey $sftpHostKey)) {
            Write-Log "Помилка пiдключення до SFTP - пропускаємо завантаження" -Level "ERROR"
        } else {
            $uploadSuccess = 0
            $uploadTotal = 0
            
            # Завантаження VETOFFICE
            if ($results.ContainsKey("VETOFFICE") -and $results["VETOFFICE"].ArchiveSuccess -and $results["VETOFFICE"].HashSuccess) {
                $uploadTotal += 2
                
                Write-Log "--- ЗАВАНТАЖЕННЯ АРХІВУ VETOFFICE НА SFTP ---"
                $archiveUpload = Send-FileViaWinSCP -WinSCPPath $winSCPPath -RepositorySFTPUrl $sftpUrl -HostKey $sftpHostKey -LocalFilePath $results["VETOFFICE"].ArchivePath -RemoteDirectory $sftpDirectories["Model"]
                if ($archiveUpload) { $uploadSuccess++ }
                
                Write-Log "--- ЗАВАНТАЖЕННЯ ХЕШУ АРХІВУ VETOFFICE НА SFTP ---"
                $hashUpload = Send-FileViaWinSCP -WinSCPPath $winSCPPath -RepositorySFTPUrl $sftpUrl -HostKey $sftpHostKey -LocalFilePath $results["VETOFFICE"].HashPath -RemoteDirectory $sftpDirectories["Model"]
                if ($hashUpload) { $uploadSuccess++ }
            }
            
            # Завантаження BLOG
            if ($results.ContainsKey("BLOG") -and $results["BLOG"].ArchiveSuccess -and $results["BLOG"].HashSuccess) {
                $uploadTotal += 2
                
                Write-Log "--- ЗАВАНТАЖЕННЯ АРХІВУ BLOG НА SFTP ---"
                $archiveUpload = Send-FileViaWinSCP -WinSCPPath $winSCPPath -RepositorySFTPUrl $sftpUrl -HostKey $sftpHostKey -LocalFilePath $results["BLOG"].ArchivePath -RemoteDirectory $sftpDirectories["BLOG"]
                if ($archiveUpload) { $uploadSuccess++ }
                
                Write-Log "--- ЗАВАНТАЖЕННЯ ХЕШУ АРХІВУ BLOG НА SFTP ---"
                $hashUpload = Send-FileViaWinSCP -WinSCPPath $winSCPPath -RepositorySFTPUrl $sftpUrl -HostKey $sftpHostKey -LocalFilePath $results["BLOG"].HashPath -RemoteDirectory $sftpDirectories["BLOG"]
                if ($hashUpload) { $uploadSuccess++ }
            }
            
            Write-Log "--- ПІДСУМОК ЗАВАНТАЖЕННЯ НА SFTP ---"
            if ($uploadTotal -gt 0) {
                Write-Log "Завантажено $uploadSuccess з $uploadTotal файлiв на SFTP" -Level "SUCCESS"
            } else {
                Write-Log "Немає файлiв для завантаження на SFTP" -Level "WARNING"
            }
        }
        Write-Log "==="
    } else {
        Write-Log "=== ЗАВАНТАЖЕННЯ НА SFTP ===" -LogOnly
        Write-Log "Завантаження на SFTP вимкнено в налаштуваннях" -Level "INFO" -LogOnly
        Write-Log "===" -LogOnly
    }
    
    if ($global:DryRun -and $enableNetworkCopy) {
        Write-Log "=== КОПIЮВАННЯ В МЕРЕЖЕВУ ПАПКУ ==="
        Write-Log "DRY-RUN: копiювання в мережеву папку пропущено" -Level "WARNING"
        Write-Log "==="
    }
    # Завантаження в мережеву папку (Samba)
    Set-ArchivWindowTitle -Stage "Копiювання в мережу"
    if ($enableNetworkCopy -and -not $global:DryRun) {
        Write-Log "=== КОПIЮВАННЯ В МЕРЕЖЕВУ ПАПКУ ==="
        Write-Log "--- ПIДКЛЮЧЕННЯ МЕРЕЖЕВОГО ДИСКА ---"
        
        # Підключаємо мережевий диск
        $connected = Connect-NetworkDrive
        
        if (-not $connected) {
            Write-Log "Не вдалося пiдключити мережевий диск - пропускаємо копiювання" -Level "ERROR"
        } else {
            $copySuccess = 0
            $copyTotal = 0
            
            # Копіювання VETOFFICE
            if ($results.ContainsKey("VETOFFICE") -and $results["VETOFFICE"].ArchiveSuccess -and $results["VETOFFICE"].HashSuccess) {
                $copyTotal += 2
                
                Write-Log "--- КОПIЮВАННЯ В МЕРЕЖЕВУ ПАПКУ АРХІВУ VETOFFICE ---"
                $archiveCopy = Copy-ToNetworkDrive -SourcePath $results["VETOFFICE"].ArchivePath -DestinationFolder "Model"
                if ($archiveCopy) { $copySuccess++ }
                
                Write-Log "--- КОПIЮВАННЯ В МЕРЕЖЕВУ ПАПКУ ХЕШУ АРХІВУ VETOFFICE ---"
                $hashCopy = Copy-ToNetworkDrive -SourcePath $results["VETOFFICE"].HashPath -DestinationFolder "Model"
                if ($hashCopy) { $copySuccess++ }
            }
            
            # Копіювання BLOG
            if ($results.ContainsKey("BLOG") -and $results["BLOG"].ArchiveSuccess -and $results["BLOG"].HashSuccess) {
                $copyTotal += 2
                
                Write-Log "--- КОПIЮВАННЯ В МЕРЕЖЕВУ ПАПКУ АРХІВУ BLOG ---"
                $archiveCopy = Copy-ToNetworkDrive -SourcePath $results["BLOG"].ArchivePath -DestinationFolder "BLOG"
                if ($archiveCopy) { $copySuccess++ }
                
                Write-Log "--- КОПIЮВАННЯ В МЕРЕЖЕВУ ПАПКУ ХЕШУ АРХІВУ BLOG ---"
                $hashCopy = Copy-ToNetworkDrive -SourcePath $results["BLOG"].HashPath -DestinationFolder "BLOG"
                if ($hashCopy) { $copySuccess++ }
            }
            
            Write-Log "=== ПІДСУМОК КОПIЮВАННЯ В МЕРЕЖЕВУ ПАПКУ ==="
            
            if ($copyTotal -gt 0) {
                $percentage = [math]::Round(($copySuccess / $copyTotal) * 100, 1)
                Write-Log "Скопiйовано $copySuccess з $copyTotal файлiв ($percentage%) в мережеву папку" -Level "SUCCESS"
            } else {
                Write-Log "Немає файлiв для копiювання в мережеву папку" -Level "WARNING"
            }
            
            # Відключаємо диск
            Disconnect-NetworkDrive | Out-Null
        }
        Write-Log "==="
    } else {
        Write-Log "=== КОПIЮВАННЯ В МЕРЕЖЕВУ ПАПКУ ===" -LogOnly
        Write-Log "Копiювання в мережеву папку вимкнено в налаштуваннях" -Level "INFO" -LogOnly
        Write-Log "===" -LogOnly
    }
    
    Set-ArchivWindowTitle -Stage "Синхронiзацiя BAZA"
    # >>> BAZA CONSOLE VISIBILITY PATCH: BEGIN
    if ((-not $excludeComponents.BAZA) -or ((-not $excludeComponents.BAZA_Network) -and $enableNetworkCopy)) {
    Write-Log "=== СИНХРОНІЗАЦІЯ ФАЙЛІВ BAZA ==="
    
    # Синхронізація BAZA (тільки якщо не вимкнена)
    if ($global:DryRun -and -not $excludeComponents.BAZA) {
        Write-Log "DRY-RUN: локальна синхронiзацiя BAZA пропущена" -Level "WARNING"
        $syncLocalSuccess = $true
    } elseif (-not $excludeComponents.BAZA) {
        # ЛОКАЛЬНА синхронізація BAZA
        $syncLocalSuccess = Sync-Folders -SourcePath $bazaPaths.Source -DestinationPath $bazaPaths.Destination_Local -SyncType "LOCAL"

        if ($syncLocalSuccess) {
            Write-Log "Локальна синхронiзацiя BAZA успiшна" -Level "SUCCESS"
        } else {
            Write-Log "Помилка локальної синхронiзацiї BAZA" -Level "WARNING"
        }
    } else {
        Write-Log "Локальна синхронiзацiя BAZA вимкнена в налаштуваннях" -Level "INFO"
    }
    
    # МЕРЕЖЕВА синхронізація BAZA
    if ($global:DryRun -and -not $excludeComponents.BAZA_Network -and $enableNetworkCopy) {
        Write-Log "DRY-RUN: мережева синхронiзацiя BAZA пропущена" -Level "WARNING"
        $syncNetworkSuccess = $true
    } elseif (-not $excludeComponents.BAZA_Network -and $enableNetworkCopy) {
        $syncNetworkSuccess = Sync-Folders -SourcePath $bazaPaths.Source -DestinationPath $bazaPaths.Destination_Network -SyncType "NETWORK"

        if ($syncNetworkSuccess) {
            Write-Log "Мережева синхронiзацiя BAZA успiшна" -Level "SUCCESS"
        } else {
            Write-Log "Помилка мережевої синхронiзацiї BAZA" -Level "WARNING"
        }
    } elseif ($excludeComponents.BAZA_Network) {
        Write-Log "Мережева синхронiзацiя BAZA вимкнена в налаштуваннях" -Level "INFO"
    } elseif (-not $enableNetworkCopy) {
        Write-Log "Мережева синхронiзацiя BAZA вимкнена (копiювання в мережу вимкнено)" -Level "INFO"
    }
    
    Write-Log "==="
    
    # Очищення старих архівів
    Set-ArchivWindowTitle -Stage "Очищення старих архiвiв"
    } else {
        Write-Log "Синхронiзацiя BAZA вимкнена в налаштуваннях" -Level "DEBUG" -LogOnly
    }
    # <<< BAZA CONSOLE VISIBILITY PATCH: END
    $archiveRetentionKeepCount = Get-ArchivConfigValue -Name "archiveRetentionKeepCount" -DefaultValue $archiveVersions
    $archiveRetentionKeepDays = Get-ArchivConfigValue -Name "archiveRetentionKeepDays" -DefaultValue 0

    if ($enableArchiveDeletion) {
        Write-Log "=== RETENTION АРХIВIВ ==="

        foreach ($archiveType in $archiveDirs.Keys) {
            # Пропускаємо вимкнені компоненти
            $componentEnabled = $true
            switch ($archiveType) {
                "Model" { $componentEnabled = -not $excludeComponents.VETOFFICE }
                "Blog" { $componentEnabled = -not $excludeComponents.Blog }
            }

            if ($componentEnabled) {
                $archiveDisplayName = switch ($archiveType) {
                    "Model" { "VETOFFICE" }
                    "Blog"  { "BLOG" }
                    default { $archiveType.ToUpperInvariant() }
                }

                Invoke-ArchivArchiveRetention `
                    -Path $archiveDirs[$archiveType] `
                    -ArchiveType $archiveType `
                    -DisplayName $archiveDisplayName `
                    -KeepCount ([int]$archiveRetentionKeepCount) `
                    -KeepDays ([int]$archiveRetentionKeepDays) | Out-Null
            } else {
                Write-Log "Retention $archiveType пропущено: компонент вимкнено" -Level "DEBUG" -LogOnly
            }
        }

        Write-Log "==="
    } else {
        Write-Log "=== RETENTION АРХIВIВ ===" -LogOnly
        Write-Log "Retention архiвiв вимкнено в налаштуваннях" -Level "INFO" -LogOnly
        Write-Log "===" -LogOnly
    }
    
    Set-ArchivWindowTitle -Stage "Очищення старих логiв"
    if ($global:DryRun) {
        Write-Log "=== ОЧИЩЕННЯ СТАРИХ ЛОГIВ ==="
        Write-Log "DRY-RUN: очищення старих логiв пропущено" -Level "WARNING"
        Write-Log "==="
    } else {
        Write-Log "=== ОЧИЩЕННЯ СТАРИХ ЛОГIВ ==="
        Remove-OldFiles -Path $logPath -Filter "ARCHIV_VETOFFICE_*.log" -KeepCount $logRetentionDays -FileType "логiв" | Out-Null
        Write-Log "==="
    }
    
    # Завершення
    $scriptEndTime = Get-Date
    $duration = $scriptEndTime - $scriptStartTime
    
    Set-ArchivWindowTitle -Stage "Завершено"
    Write-Log "=== ЗАВЕРШЕННЯ РОБОТИ СКРИПТА ==="
    Write-Log "Час початку: $($scriptStartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -NoTimestamp
    Write-Log "Час завершення: $($scriptEndTime.ToString('yyyy-MM-dd HH:mm:ss'))" -NoTimestamp
    Write-Log "Тривалiсть: $($duration.ToString('hh\:mm\:ss'))" -NoTimestamp
    Write-Log "" -NoTimestamp
    
    # Детальний підсумок
    $successArchives = ($results.Values | Where-Object { $_.ArchiveSuccess }).Count
    $successHashes = ($results.Values | Where-Object { $_.HashSuccess }).Count
    $totalArchives = $results.Count
    
    # Отримуємо статистику SFTP
    $uploadSuccess = 0
    $uploadTotal = 0
    Set-ArchivWindowTitle -Stage "SFTP"
    if ($enableSFTPUpload -and -not $global:DryRun) {
        if ($results.ContainsKey("VETOFFICE") -and $results["VETOFFICE"].ArchiveSuccess -and $results["VETOFFICE"].HashSuccess) {
            $uploadTotal += 2
            $uploadSuccess += 2
        }
        if ($results.ContainsKey("BLOG") -and $results["BLOG"].ArchiveSuccess -and $results["BLOG"].HashSuccess) {
            $uploadTotal += 2
            $uploadSuccess += 2
        }
    }
    
    # Отримуємо статистику мережевого копіювання
    $copySuccess = 0
    $copyTotal = 0
    Set-ArchivWindowTitle -Stage "Копiювання в мережу"
    if ($enableNetworkCopy -and -not $global:DryRun) {
        if ($results.ContainsKey("VETOFFICE") -and $results["VETOFFICE"].ArchiveSuccess -and $results["VETOFFICE"].HashSuccess) {
            $copyTotal += 2
            $copySuccess += 2
        }
        if ($results.ContainsKey("BLOG") -and $results["BLOG"].ArchiveSuccess -and $results["BLOG"].HashSuccess) {
            $copyTotal += 2
            $copySuccess += 2
        }
    }
    
    if ($global:DryRun) {
        Write-Log "Створено архiвiв: DRY-RUN, фактично не створювались" -NoTimestamp
    } else {
        Write-Log "Створено архiвiв: $(if ($successArchives -eq $totalArchives -and $totalArchives -gt 0) {'успішно'} else {'$successArchives з $totalArchives'})" -NoTimestamp
    }
    if ($global:DryRun) {
        Write-Log "Створено хешу для архівів: DRY-RUN, фактично не створювались" -NoTimestamp
    } else {
        Write-Log "Створено хешу для архівів: $(if ($successHashes -eq $totalArchives -and $totalArchives -gt 0) {'успішно'} else {'$successHashes з $totalArchives'})" -NoTimestamp
    }
    
    Set-ArchivWindowTitle -Stage "SFTP"
    if ($enableSFTPUpload -and -not $global:DryRun) {
        Write-Log "Завантаження на SFTP: $(if ($uploadSuccess -eq $uploadTotal -and $uploadTotal -gt 0) {'успiшно'} elseif ($uploadTotal -eq 0) {'немає файлів'} else {'$uploadSuccess з $uploadTotal'})" -NoTimestamp
    } else {
        Write-Log "Завантаження на SFTP: вимкнено" -Level "DEBUG" -LogOnly
    }
    
    Set-ArchivWindowTitle -Stage "Копiювання в мережу"
    if ($enableNetworkCopy -and -not $global:DryRun) {
        Write-Log "Завантаження в мережеву папку: $(if ($copySuccess -eq $copyTotal -and $copyTotal -gt 0) {'успiшно'} elseif ($copyTotal -eq 0) {'немає файлів'} else {'$copySuccess з $copyTotal'})" -NoTimestamp
    } else {
        Write-Log "Завантаження в мережеву папку: вимкнено" -Level "DEBUG" -LogOnly
    }
    
    if ($global:DryRun -and -not $excludeComponents.BAZA) {
        Write-Log "DRY-RUN: локальна синхронiзацiя BAZA пропущена" -Level "WARNING"
        $syncLocalSuccess = $true
    } elseif (-not $excludeComponents.BAZA) {
        Write-Log "Локальна синхронiзацiя BAZA: $(if ($syncLocalSuccess) {'успiшна'} else {'з помилками'})" -NoTimestamp
    } else {
        Write-Log "Локальна синхронiзацiя BAZA: вимкнено" -Level "DEBUG" -LogOnly
    }
    
    if ($global:DryRun -and -not $excludeComponents.BAZA_Network -and $enableNetworkCopy) {
        Write-Log "DRY-RUN: мережева синхронiзацiя BAZA пропущена" -Level "WARNING"
        $syncNetworkSuccess = $true
    } elseif (-not $excludeComponents.BAZA_Network -and $enableNetworkCopy) {
        Write-Log "Мережева синхронiзацiя BAZA: $(if ($syncNetworkSuccess) {'успiшна'} else {'з помилками'})" -NoTimestamp
    } else {
        Write-Log "Мережева синхронiзацiя BAZA: вимкнено" -Level "DEBUG" -LogOnly
    }
    
    Write-Log "" -NoTimestamp
    New-ArchivJsonReport `
        -StartedAt $scriptStartTime `
        -FinishedAt $scriptEndTime `
        -Results $results `
        -Archives $archives `
        -ReportPath $global:jsonReportFile | Out-Null

    
    Update-ArchivHistory -ReportPath $global:jsonReportFile | Out-Null
    Test-ArchivBackupHealth
Write-Log "JSON-звiт: $global:jsonReportFile" -NoTimestamp
    Write-Log "Лог-файл: $logFile" -NoTimestamp
    Write-Log "==="

    # Пауза тільки при інтерактивному запуску
    $isInteractive = [Environment]::UserInteractive
    if ($isInteractive) {
        Write-Host "`nНатиснiть будь-яку клавiшу для закриття..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}

# =============================================
# ОБРОБКА ПАРАМЕТРІВ КОМАНДНОГО РЯДКА
# =============================================

function Show-Help {
    Write-Host "`n=== ВИКОРИСТАННЯ СКРИПТА ARCHIV_VETOFFICE ===" -ForegroundColor Yellow
    Write-Host "`nОсновнi параметри:" -ForegroundColor Cyan
    Write-Host "  Без параметрiв           - Запуск архiвацiї" -ForegroundColor White
    Write-Host "  -Schedule                - Додати в Планувальник завдань" -ForegroundColor White
    Write-Host "  -ShowTasks               - Показати завдання в Планувальнику" -ForegroundColor White
    Write-Host "  -RemoveTask              - Видалити завдання з Планувальника" -ForegroundColor White
    Write-Host "  -DryRun                  - Тестовий запуск без створення архiвiв/хешiв/копiювання" -ForegroundColor White
    Write-Host "  -Help, -?, /?            - Показати цю довiдку" -ForegroundColor White
    
    Write-Host "`nПриклади:" -ForegroundColor Cyan
    Write-Host "  .\ARCHIV_VETOFFICE.ps1                    - Запуск архiвацiї" -ForegroundColor Gray
    Write-Host "  .\ARCHIV_VETOFFICE.ps1 -Schedule         - Додати в Планувальник" -ForegroundColor Gray
    Write-Host "  .\ARCHIV_VETOFFICE.ps1 -ShowTasks        - Перелiк завдань" -ForegroundColor Gray
    Write-Host "  .\ARCHIV_VETOFFICE.ps1 -DryRun           - Тест без створення архiвiв
  .\ARCHIV_VETOFFICE.ps1 -RemoveTask       - Видалити завдання" -ForegroundColor Gray
    
    Write-Host "`nФайл конфiгурацiї: $configPath" -ForegroundColor Gray
    Write-Host "Версiя скрипта: $ScriptVersion вiд $ScriptDate`n" -ForegroundColor Gray
}

# >>> DRY-RUN MODE PATCH: BEGIN
$global:DryRun = $false

if ($args -contains "-DryRun" -or $args -contains "--dry-run" -or $args -contains "/dry-run") {
    $global:DryRun = $true
    $args = @($args | Where-Object {
        $_ -notin @("-DryRun", "--dry-run", "/dry-run")
    })
}
# <<< DRY-RUN MODE PATCH: END
# Обробка параметрів командного рядка
if ($args.Count -gt 0) {
    $param = $args[0].ToLower()
    
    switch ($param) {
        "-schedule" {
            Write-Host "`n=== ДОДАВАННЯ СКРИПТА ДО ПЛАНУВАЛЬНИКА ЗАВДАНЬ ===" -ForegroundColor Yellow
            Write-Host "Скрипт буде додано до Планувальника для автоматичного запуску.`n" -ForegroundColor White
            
            $confirmation = Read-Host "Продовжити? (Y/N)"
            if ($confirmation -eq "Y" -or $confirmation -eq "y") {
                Add-ToTaskScheduler
            } else {
                Write-Host "Скасовано." -ForegroundColor Yellow
            }
            Exit 0
        }
        
        "-showtasks" {
            Show-TaskSchedulerInfo
            Exit 0
        }
        
        "-removetask" {
            Write-Host "`n=== ВИДАЛЕННЯ ЗАВДАНЬ З ПЛАНУВАЛЬНИКА ===" -ForegroundColor Yellow
            Write-Host "Ви можете видалити одне або всi завдання архiвацiї.`n" -ForegroundColor White
            
            $confirmation = Read-Host "Продовжити? (Y/N)"
            if ($confirmation -eq "Y" -or $confirmation -eq "y") {
                Remove-FromTaskScheduler
            } else {
                Write-Host "Скасовано." -ForegroundColor Yellow
            }
            Exit 0
        }
        
        "-help" { Show-Help; Exit 0 }
        "-?" { Show-Help; Exit 0 }
        "/?" { Show-Help; Exit 0 }
        
        default {
            Write-Host "`nНевiдомий параметр: $param" -ForegroundColor Red
            Show-Help
            Exit 1
        }
    }
}

# Запуск головної функції (якщо не було параметрів)
Main

