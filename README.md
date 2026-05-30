# Скрипт архівації для VetOffice

PowerShell-скрипт для архівації даних VetOffice, створення SHA512-хешів, очищення старих архівів і логів, а також опціонального завантаження результатів на SFTP або в мережеву папку.

Проєкт розрахований на Windows Server / Windows Workstation і використовує `7za.exe` для створення архівів та `WinSCP.com` для SFTP-завантаження.

## Можливості

- Архівація основної папки VetOffice / Model.
- Опціональна архівація BLOG.
- Створення `.sha512` файлів для кожного архіву.
- Перевірка вільного місця перед архівацією.
- Очищення старих архівів і логів.
- Опціональне SFTP-завантаження через WinSCP.
- Опціональне копіювання в мережеву папку.
- Опціональна синхронізація BAZA.
- Watchdog для завершення дочірніх процесів `7za.exe`, `WinSCP.com`, `robocopy.exe` при закритті PowerShell.
- Компактний формат виводу в термінал:
  ```text
  [INFO] Повідомлення
  [SUCCESS] Повідомлення
  ```
- Повний timestamp у лог-файлі.
- Відображення поточного етапу в заголовку вікна PowerShell.

## Структура проєкту

Рекомендована структура:

```text
ARCHIV/
├── ARCHIV_VETOFFICE.ps1
├── ARCHIV_VETOFFICE.config.example.ps1
├── ARCHIV_VETOFFICE.config.ps1
├── Tools/
│   ├── 7za.exe
│   ├── WinSCP.com
│   ├── WinSCP.exe
│   └── WinSCP.uk
├── LOGS/
├── VETOFFICE/
└── BLOG/
```

`ARCHIV_VETOFFICE.config.ps1` містить локальні шляхи, паролі та параметри середовища, тому його не слід додавати в Git, якщо там є реальні секрети.

## Швидкий старт

### 1. Перейдіть у гілку `vetcontrol`

```powershell
cd E:\VetOffice\ARCHIV
git checkout vetcontrol
git pull
```

### 2. Створіть реальний конфіг

```powershell
Copy-Item .\ARCHIV_VETOFFICE.config.example.ps1 .\ARCHIV_VETOFFICE.config.ps1
```

Відредагуйте:

```powershell
notepad .\ARCHIV_VETOFFICE.config.ps1
```

Мінімально потрібно перевірити:

```powershell
$rootPath
$toolsPath
$sourcePaths
$archiveDirs
$archivePrefix
$freeSpaceReserveGB
$archiveSpaceMultiplier
$excludeComponents
```

### 3. Перевірте наявність утиліт

У папці `Tools` мають бути:

```text
7za.exe
WinSCP.com
WinSCP.exe
```

### 4. Запустіть скрипт

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ARCHIV_VETOFFICE.ps1
```

## Конфігурація

Основні параметри знаходяться у файлі:

```text
ARCHIV_VETOFFICE.config.ps1
```

### Основні шляхи

```powershell
$rootPath = "E:\VetOffice"
$toolsPath = Join-Path $PSScriptRoot "Tools"
$logPath = Join-Path $PSScriptRoot "LOGS"
$archivPath = $PSScriptRoot
```

### Джерела даних

```powershell
$sourcePaths = @{
    Model = Join-Path $rootPath "VETOFFICE"
    Blog  = Join-Path $rootPath "BLOG"
}
```

### Каталоги архівів

```powershell
$archiveDirs = @{
    Model = Join-Path $archivPath "VETOFFICE"
    Blog  = Join-Path $archivPath "BLOG"
}
```

### Параметри архівації

```powershell
$archivePrefix = "vetcontrol_dev_pnmgu_v2508"
$archiveParams = "a -tzip -mx=5 -mmt=on"
$archiveVersions = 7
$enableArchiveDeletion = $true
```

Фінальні імена архівів мають вигляд:

```text
vetcontrol_dev_pnmgu_v2508_20260529_2318.mdz
vetcontrol_dev_pnmgu_v2508_blog_20260529_2318.mdz
```

### Перевірка вільного місця

```powershell
$freeSpaceReserveGB = 5
$archiveSpaceMultiplier = 1.2
```

Скрипт перевіряє, що на диску архіву є достатній резерв:

```text
max(розмір_джерела × archiveSpaceMultiplier, freeSpaceReserveGB)
```

У стандартному режимі в терміналі виводиться один загальний рядок:

```text
[INFO] Параметри перевiрки мiсця: резерв=5 GB; множник=1.2
```

А для кожного архіву — тільки фактичні значення:

```text
[INFO] Розмiр джерела: 505,96 MB
[INFO] Вiльно на диску архiву: 85,66 GB
```

## Увімкнення / вимкнення компонентів

```powershell
$excludeComponents = @{
    VETOFFICE    = $false
    Blog         = $false
    BAZA         = $true
    BAZA_Network = $true
}
```

Значення `$true` означає, що компонент вимкнено.

Наприклад, щоб архівувати тільки VetOffice без BLOG:

```powershell
$excludeComponents = @{
    VETOFFICE    = $false
    Blog         = $true
    BAZA         = $true
    BAZA_Network = $true
}
```

## SFTP

Щоб увімкнути SFTP-завантаження:

```powershell
$enableSFTPUpload = $true
```

Налаштуйте:

```powershell
$Login = "sftp_user"
$Password = "CHANGE_ME"
$sftpUrl = "sftp://backup.example.com/"
$sftpHostKey = "ssh-ed25519 255 SHA256:CHANGE_ME"

$sftpDirectories = @{
    Model = "/backup/VetOffice/Model"
    BLOG  = "/backup/VetOffice/BLOG"
}
```

Реальні паролі не слід зберігати в репозиторії. Git не сейф, Git — пам’ять слона з інтернетом.

## Мережеве копіювання

Щоб увімкнути копіювання в мережеву папку:

```powershell
$enableNetworkCopy = $true
```

Налаштуйте:

```powershell
$networkCopyConfig = @{
    NetworkPath = "\\SERVER\Backup\VetOffice"
    Username    = ""
    Password    = ""
    MaxRetries  = 3
    RetryDelay  = 10
}
```

## Логування

Рівень логування:

```powershell
$global:LogLevel = "INFO"
```

Доступні режими:

```text
DEBUG
INFO
WARNING
ERROR
```

У терміналі використовується короткий формат:

```text
[INFO] Повідомлення
```

У файлі логу зберігається повний timestamp:

```text
[2026-05-29 23:18:07] [INFO] Повідомлення
```

Логи створюються у:

```text
LOGS\ARCHIV_VETOFFICE_yyyyMMdd_HHmm.log
```

## Watchdog і завершення процесів

Скрипт запускає watchdog, який стежить за основним PowerShell-процесом. Якщо PowerShell буде закритий, watchdog завершує дочірні процеси:

```text
7za.exe
7z.exe
WinSCP.com
robocopy.exe
```

Це потрібно, щоб архіватор не залишався працювати після закриття вікна.

## Запуск через Планувальник завдань

Скрипт має режим додавання в Task Scheduler:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ARCHIV_VETOFFICE.ps1 -Schedule
```

Переглянути завдання:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ARCHIV_VETOFFICE.ps1 -ShowTasks
```

Видалити завдання:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ARCHIV_VETOFFICE.ps1 -RemoveTask
```

## Відновлення файлу з GitHub

Якщо локальний `ARCHIV_VETOFFICE.ps1` пошкоджено:

```powershell
git checkout vetcontrol
git pull
git restore --source=origin/vetcontrol -- ARCHIV_VETOFFICE.ps1
```

Або:

```powershell
git checkout origin/vetcontrol -- ARCHIV_VETOFFICE.ps1
```

## Команди Git для роботи з гілкою

Перейти у гілку:

```powershell
git checkout vetcontrol
```

Перевірити стан:

```powershell
git status
```

Додати зміни:

```powershell
git add ARCHIV_VETOFFICE.ps1 ARCHIV_VETOFFICE.config.example.ps1 README.md
```

Коміт:

```powershell
git commit -m "Update VetOffice archive documentation and config example"
```

Push:

```powershell
git push
```

Перевірити файли у віддаленій гілці:

```powershell
git ls-tree -r --name-only origin/vetcontrol
```

## Безпека

Не додавайте до Git:

```text
ARCHIV_VETOFFICE.config.ps1
LOGS/
VETOFFICE/
BLOG/
*.mdz
*.sha512
```

Рекомендовано мати в `.gitignore`:

```gitignore
ARCHIV_VETOFFICE.config.ps1
LOGS/
VETOFFICE/
BLOG/
*.mdz
*.sha512
*.bak*
*.tmp
```

## Типовий результат у консолі

```text
=== АРХIВАЦIЯ ТА СТВОРЕННЯ ХЕШУ ===
[INFO] Параметри перевiрки мiсця: резерв=5 GB; множник=1.2
--- АРХIВАЦIЯ VETOFFICE ---
[INFO] Розмiр джерела: 505,96 MB
[INFO] Вiльно на диску архiву: 85,66 GB
[INFO] Створення архiву: vetcontrol_dev_pnmgu_v2508_20260529_2318.mdz
[SUCCESS] Архiв створено: E:\VetOffice\ARCHIV\VETOFFICE\vetcontrol_dev_pnmgu_v2508_20260529_2318.mdz
--- СТВОРЕННЯ ХЕШУ VETOFFICE ---
[SUCCESS] Хеш створено: E:\VetOffice\ARCHIV\VETOFFICE\vetcontrol_dev_pnmgu_v2508_20260529_2318.mdz.sha512
```

## Примітки

- Запускати краще у звичайному PowerShell / Windows Terminal, не у PowerShell ISE.
- Для бойового режиму рекомендовано використовувати Task Scheduler.
- Перед змінами в коді бажано створювати окремий commit або тег.


## Що нового у v2.2

### Нові можливості

* DRY-RUN режим для швидкого тестування без створення архівів.
* Зберігання паролів через Windows Credential Manager.
* Перевірка цілісності архівів 7-Zip (`7z t`).
* Створення SHA512 контрольних сум.
* Автоматична перевірка SHA512 після створення архівів.
* JSON-звіти по кожному запуску.
* Історія запусків (`history.json`).
* Контроль стану резервних копій (Backup Health Check).
* Відображення статистики стиснення.
* Покращений заголовок вікна під час архівації.
* Скорочений та більш інформативний консольний вивід.

### Нові файли

```text
LOGS\
├── ARCHIV_VETOFFICE_YYYYMMDD_HHMM.log
├── ARCHIV_VETOFFICE_YYYYMMDD_HHMM.json
└── history.json
```

### Нові параметри конфігурації

```powershell
# Тестування без створення архівів
$dryRun = $false

# Перевірка архіву після створення
$enableArchiveIntegrityTest = $true
```

### Перевірка архіву

Після створення архіву виконується:

```text
7z t archive.mdz
```

При успішній перевірці:

```text
[SUCCESS] Перевiрка архiву пройдена
```

### Перевірка SHA512

Після створення файлу `.sha512` виконується повторний розрахунок контрольної суми та порівняння з записаним значенням.

При успішній перевірці:

```text
[SUCCESS] Контрольна сума SHA512 збiгається
```

### Поточний статус

Реліз: v2.2

Стан: Stable

Основні функції:

* Архівація VETOFFICE
* Архівація BLOG
* SHA512
* Перевірка архівів
* JSON-звіти
* History
* Backup Health Check
* Credential Manager
* DRY-RUN

### План для v2.3

* Retention політики для архівів
* HTML Dashboard
* Telegram повідомлення
* Email повідомлення
* Каталог архівів (index.json)
