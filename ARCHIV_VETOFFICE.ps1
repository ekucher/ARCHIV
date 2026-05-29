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

        Write-Host "[WATCHDOG] Started for PowerShell PID=$ParentPid" -ForegroundColor DarkGray
    }
    catch {
        Write-Host "[WATCHDOG] Failed to start: $($_.Exception.Message)" -ForegroundColor Yellow
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
        [double]$MinFreeSpaceGB = 20
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

function New-Archive {
    param(
        [string]$SourcePath,
        [string]$ArchivePath,
        [string]$ArchiveName,
        [string]$ArcPath,
        [string]$ArcParams,
        [double]$ReserveMultiplier = 1.2,
        [double]$MinFreeSpaceGB = 20
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

    Write-Log "Створення архiву: $ArchiveName"
    
    $fullArchivePath = Join-Path $ArchivePath $ArchiveName
    
    try {
        $arguments = "$ArcParams `"$fullArchivePath`" `"$SourcePath`""
        
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
        $standardOutput = $process.StandardOutput.ReadToEnd()
        $errorOutput = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        
        if ($process.ExitCode -eq 0) {
            Write-Log "Архiв створено: $fullArchivePath" -Level "SUCCESS"
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
    $password = $networkCopyConfig.Password
    
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
# ОСНОВНА ЛОГІКА
# =============================================

function Main {
    # Ініціалізація
    $scriptStartTime = Get-Date
    $now = Get-Date -Format "yyyyMMdd_HHmm"
    $global:logFile = "$logPath\ARCHIV_VETOFFICE_$now.log"
    
    Write-Log "==="
    Write-Log "=== ПОЧАТОК РОБОТИ СКРИПТА ARCHIV_VETOFFICE v.$ScriptVersion ==="
    Write-Log "Файл конфiгурацiї: $configPath" -Level "INFO"
    Write-Log "==="
    
    Write-Log "=== ОПЦIЇ СКРИПТА ==="
    Write-Log "Версiя та дата скрипта: $ScriptVersion вiд $ScriptDate" -NoTimestamp
    Write-Log "Час початку: $($scriptStartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -NoTimestamp
    Write-Log "Кореневий каталог: $rootPath" -NoTimestamp
    Write-Log "Режим логування: $LogLevel" -NoTimestamp
    Write-Log "Копiювання в мережу: $(if ($enableNetworkCopy) {'УВIМКНЕНО'} else {'ВИМКНЕНО'})" -NoTimestamp
    Write-Log "Синхронiзацiя BAZA в мережу: $(if ($excludeComponents.BAZA_Network) {'ВИМКНЕНО'} else {'УВIМКНЕНО'})" -NoTimestamp
    Write-Log "Синхронiзацiя BAZA локальна: $(if ($excludeComponents.BAZA) {'ВИМКНЕНО'} else {'УВIМКНЕНО'})" -NoTimestamp
    Write-Log "==="
    
    # ОЧИЩЕННЯ СТАРИХ ЛОГІВ - виконується в кінці
    
    # Перевірка шляхів
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
    Write-Log "Параметри перевiрки мiсця: резерв=$freeSpaceReserveGB GB; множник=$archiveSpaceMultiplier" -Level "INFO"
        
    foreach ($archive in $archives) {
        Write-Log "--- АРХIВАЦIЯ $($archive.Type) ---"

        $success = New-Archive `
            -SourcePath $archive.Source `
            -ArchivePath $archive.Destination `
            -ArchiveName $archive.Name `
            -ArcPath $arcPath `
            -ArcParams $archiveParams `
            -ReserveMultiplier $archiveSpaceMultiplier `
            -MinFreeSpaceGB $freeSpaceReserveGB
        
        if ($success) {
            Write-Log "--- СТВОРЕННЯ ХЕШУ $($archive.Type) ---"
            $archivePath = Join-Path $archive.Destination $archive.Name
            $hashPath = "$archivePath.sha512"
            $hashSuccess = New-SHA512Hash -FilePath $archivePath -HashFilePath $hashPath
            
            $results[$archive.Type] = @{
                ArchivePath = $archivePath
                HashPath = $hashPath
                ArchiveSuccess = $success
                HashSuccess = $hashSuccess
            }
        } else {
            $results[$archive.Type] = @{
                ArchiveSuccess = $false
                HashSuccess = $false
            }
        }
    }
    
    Write-Log "==="
    
    # Завантаження на SFTP
    if ($enableSFTPUpload) {
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
    
    # Завантаження в мережеву папку (Samba)
    if ($enableNetworkCopy) {
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
    
    Write-Log "=== СИНХРОНІЗАЦІЯ ФАЙЛІВ BAZA ==="
    
    # Синхронізація BAZA (тільки якщо не вимкнена)
    if (-not $excludeComponents.BAZA) {
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
    if (-not $excludeComponents.BAZA_Network -and $enableNetworkCopy) {
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
    if ($enableArchiveDeletion) {
        Write-Log "=== ОЧИЩЕННЯ СТАРИХ АРХIВIВ ==="
        foreach ($archiveType in $archiveDirs.Keys) {
            # Пропускаємо вимкнені компоненти
            $componentEnabled = $true
            switch ($archiveType) {
                "Model" { $componentEnabled = -not $excludeComponents.VETOFFICE }
                "Blog" { $componentEnabled = -not $excludeComponents.Blog }
            }
            
            if ($componentEnabled) {
                Remove-OldFiles -Path $archiveDirs[$archiveType] -Filter "*.mdz" -KeepCount $archiveVersions -FileType "архiвiв $archiveType" | Out-Null
                Remove-OldFiles -Path $archiveDirs[$archiveType] -Filter "*.sha512" -KeepCount $archiveVersions -FileType "хеш-файлiв $archiveType" | Out-Null
            }
        }
        Write-Log "==="
    } else {
        Write-Log "=== ОЧИЩЕННЯ СТАРИХ АРХIВIВ ===" -LogOnly
        Write-Log "Видалення старих архiвiв вимкнено в налаштуваннях" -Level "INFO" -LogOnly
        Write-Log "===" -LogOnly
    }
    
    Write-Log "=== ОЧИЩЕННЯ СТАРИХ ЛОГIВ ==="
    Remove-OldFiles -Path $logPath -Filter "ARCHIV_VETOFFICE_*.log" -KeepCount $logRetentionDays -FileType "логiв" | Out-Null
    Write-Log "==="
    
    # Завершення
    $scriptEndTime = Get-Date
    $duration = $scriptEndTime - $scriptStartTime
    
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
    if ($enableSFTPUpload) {
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
    if ($enableNetworkCopy) {
        if ($results.ContainsKey("VETOFFICE") -and $results["VETOFFICE"].ArchiveSuccess -and $results["VETOFFICE"].HashSuccess) {
            $copyTotal += 2
            $copySuccess += 2
        }
        if ($results.ContainsKey("BLOG") -and $results["BLOG"].ArchiveSuccess -and $results["BLOG"].HashSuccess) {
            $copyTotal += 2
            $copySuccess += 2
        }
    }
    
    Write-Log "Створено архiвiв: $(if ($successArchives -eq $totalArchives -and $totalArchives -gt 0) {'успішно'} else {'$successArchives з $totalArchives'})" -NoTimestamp
    Write-Log "Створено хешу для архівів: $(if ($successHashes -eq $totalArchives -and $totalArchives -gt 0) {'успішно'} else {'$successHashes з $totalArchives'})" -NoTimestamp
    
    if ($enableSFTPUpload) {
        Write-Log "Завантаження на SFTP: $(if ($uploadSuccess -eq $uploadTotal -and $uploadTotal -gt 0) {'успiшно'} elseif ($uploadTotal -eq 0) {'немає файлів'} else {'$uploadSuccess з $uploadTotal'})" -NoTimestamp
    } else {
        Write-Log "Завантаження на SFTP: вимкнено" -NoTimestamp
    }
    
    if ($enableNetworkCopy) {
        Write-Log "Завантаження в мережеву папку: $(if ($copySuccess -eq $copyTotal -and $copyTotal -gt 0) {'успiшно'} elseif ($copyTotal -eq 0) {'немає файлів'} else {'$copySuccess з $copyTotal'})" -NoTimestamp
    } else {
        Write-Log "Завантаження в мережеву папку: вимкнено" -NoTimestamp
    }
    
    if (-not $excludeComponents.BAZA) {
        Write-Log "Локальна сихронізація BAZA: $(if ($syncLocalSuccess) {'успiшна'} else {'з помилками'})" -NoTimestamp
    } else {
        Write-Log "Локальна сихронізація BAZA: вимкнено" -NoTimestamp
    }
    
    if (-not $excludeComponents.BAZA_Network -and $enableNetworkCopy) {
        Write-Log "Мережева сихронізація BAZA: $(if ($syncNetworkSuccess) {'успiшна'} else {'з помилками'})" -NoTimestamp
    } else {
        Write-Log "Мережева сихронізація BAZA: вимкнено" -NoTimestamp
    }
    
    Write-Log "" -NoTimestamp
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
    Write-Host "  -Help, -?, /?            - Показати цю довiдку" -ForegroundColor White
    
    Write-Host "`nПриклади:" -ForegroundColor Cyan
    Write-Host "  .\ARCHIV_VETOFFICE.ps1                    - Запуск архiвацiї" -ForegroundColor Gray
    Write-Host "  .\ARCHIV_VETOFFICE.ps1 -Schedule         - Додати в Планувальник" -ForegroundColor Gray
    Write-Host "  .\ARCHIV_VETOFFICE.ps1 -ShowTasks        - Перелiк завдань" -ForegroundColor Gray
    Write-Host "  .\ARCHIV_VETOFFICE.ps1 -RemoveTask       - Видалити завдання" -ForegroundColor Gray
    
    Write-Host "`nФайл конфiгурацiї: $configPath" -ForegroundColor Gray
    Write-Host "Версiя скрипта: $ScriptVersion вiд $ScriptDate`n" -ForegroundColor Gray
}

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
