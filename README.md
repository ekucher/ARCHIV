# BRAVO Maintenance / ARCHIV

Монолітний PowerShell-скрипт для обслуговування середовища BRAVOSOFT/LIMS: перевірка стану системи, зупинка/запуск служб, реставрація моделі, архівація, контроль архівів, Slack-сповіщення, робота з Windows Credential Manager і запуск через Windows Task Scheduler.

Проєкт орієнтований на Windows-сервер з LIMS/BRAVO, Apache 2.4, службами BravoSoft та архівуванням через `7za.exe`.

---

## Можливості

- Автоматизоване обслуговування BRAVOSOFT/LIMS.
- Перевірка вільного місця на дисках.
- Перевірка розмірів `.md` файлів.
- Архівація моделі до/після реставрації.
- Безпечне створення архівів через тимчасовий файл:
  - створення у `ARCHIV\TEMP`;
  - перевірка через `7za t`;
  - перенесення у фінальну директорію тільки після успішної перевірки.
- Підтримка пароля архіву через Windows Credential Manager.
- Підтримка `-mhe=on` для шифрування заголовків архіву.
- SHA512-контроль архівів.
- Health-check архівів `LIMS`, `BLOG`, `BRAVOEXCH`.
- Slack-сповіщення:
  - тільки помилки;
  - усі повідомлення;
  - вимкнено.
- TLS-safe відправка Slack webhook через `Invoke-RestMethod`.
- Progress-state після аварійного вимкнення живлення.
- Встановлення задачі Windows Scheduler під окремим прихованим неінтерактивним користувачем.
- Bootstrap credential-ів для користувача планувальника.
- Локальна конфігурація через `BRAVO.config.ps1`.

---

## Основні файли

| Файл | Призначення |
|---|---|
| `BRAVO_MAINTENANCE.ps1` | Основний монолітний скрипт обслуговування |
| `BRAVO.config.example.ps1` | Приклад конфігурації без секретів |
| `BRAVO.config.ps1` | Локальний конфіг сервера, не комітити |
| `README.md` | Документація |
| `.gitignore` | Виключення runtime-файлів, логів, архівів і секретів |

---

## Структура runtime-директорій

Типова структура в `C:\LIMS\ARCHIV`:

```text
C:\LIMS\ARCHIV
├─ BAZA\
├─ BLOG\
├─ BRAVOEXCH\
├─ exchangAPI\
├─ LIMS\
├─ LOGS\
├─ STATE\
├─ TEMP\
├─ Tools\
└─ Trace\
```

Призначення:

| Директорія | Призначення |
|---|---|
| `LIMS\` | Архіви основної моделі LIMS |
| `BLOG\` | Архіви BLOG |
| `BRAVOEXCH\` | Архіви BRAVOEXCH |
| `LOGS\` | Логи роботи скрипта |
| `STATE\` | Progress-state для відновлення після збою |
| `TEMP\` | Тимчасові архіви до перевірки через `7za t` |
| `Trace\` | Оброблені trace/log файли |
| `Tools\` | Допоміжні утиліти, наприклад `7za.exe` |

---

## Вимоги

- Windows PowerShell 5.1.
- Права адміністратора для:
  - створення локального користувача планувальника;
  - налаштування прав `Log on as batch job`;
  - встановлення scheduled task;
  - керування службами.
- `7za.exe` або сумісний 7-Zip CLI.
- Доступ до директорії `C:\LIMS`.
- За потреби: Slack Incoming Webhook URL.

---

## Початкове налаштування

### 1. Скопіювати конфіг

```powershell
cd C:\LIMS\ARCHIV
Copy-Item .\BRAVO.config.example.ps1 .\BRAVO.config.ps1
notepad .\BRAVO.config.ps1
```

`BRAVO.config.ps1` є локальним файлом сервера і не має потрапляти в Git.

---

### 2. Перевірити синтаксис

```powershell
$scriptText = Get-Content -LiteralPath .\BRAVO_MAINTENANCE.ps1 -Raw

try {
    [scriptblock]::Create($scriptText) | Out-Null
    "Syntax OK"
}
catch {
    $_.Exception.Message
}
```

Очікувано:

```text
Syntax OK
```

---

## Приклад конфігурації

Фрагмент `BRAVO.config.ps1`:

```powershell
$global:BravoConfig = @{
    ObjectName = "Назва установи"
    RootLims = "C:\LIMS"

    ArchivePrefix = "example_prefix"

    # 7-Zip
    SevenZipPath = "C:\LIMS\ARCHIV\Tools\7za.exe"
    SevenZipArchiveArgs = @("a", "-t7z", "-mx=5", "-mmt=on")
    SevenZipExtractArgs = @("x", "-y")

    # Archive password
    ArchivePasswordEnabled = "on"
    ArchivePasswordEncryptHeaders = "on"
    ArchivePasswordCredentialTarget = "BRAVO/ArchivePassword"
    ArchivePassword = ""

    # Temporary verified archives
    ArchiveTempDir = "{ROOT_LIMS}\ARCHIV\TEMP"

    # Slack
    SlackMode = "errors_only"
    SlackWebhookCredentialTarget = "BRAVO/SlackWebhookUrl"
    SlackWebhookUrl = ""

    # Progress state
    ProgressStateEnabled = "on"
    ProgressStateMaxAgeHours = 72
    ProgressStateAutoResumeForScheduler = "on"

    # Health checks
    HealthCheckEnabled = "on"
    HealthCheckArchiveMaxAgeHours = 2
    HealthCheckMinFreeSpaceGB = 10
    HealthCheckDrives = @("C:", "D:", "E:")

    HealthCheckArchiveCategories = @(
        @{
            Name = "LIMS"
            Path = "{ROOT_LIMS}\ARCHIV\LIMS"
            Pattern = "{ArchivePrefix}_*.mdz"
            Exclude = @(
                "{ArchivePrefix}_before_*.mdz",
                "{ArchivePrefix}_after_*.mdz"
            )
        },
        @{
            Name = "BLOG"
            Path = "{ROOT_LIMS}\ARCHIV\BLOG"
            Pattern = "{ArchivePrefix}_blog_*.mdz"
        },
        @{
            Name = "BRAVOEXCH"
            Path = "{ROOT_LIMS}\ARCHIV\BRAVOEXCH"
            Pattern = "{ArchivePrefix}_bravoexch_*.mdz"
        }
    )
}
```

---

## Windows Credential Manager

Чутливі дані бажано зберігати не в конфігу, а в Windows Credential Manager.

### Інтерактивне збереження секретів

```powershell
.\BRAVO_MAINTENANCE.ps1 -SetupCredentials
```

Скрипт може зберігати:

- пароль архіву;
- Slack webhook URL;
- інші credential-и, якщо відповідна функція увімкнена в конфігу.

Важливо: Windows Credential Manager зберігає записи **для конкретного Windows-користувача**. Якщо задача запускається під `BRAVO_Scheduler`, секрети мають бути доступні саме цьому користувачу. Для цього використовується credential bootstrap під час встановлення scheduled task.

---

## Пароль архіву і `-mhe=on`

Якщо увімкнено:

```powershell
ArchivePasswordEnabled = "on"
ArchivePasswordEncryptHeaders = "on"
```

то під час створення архівів до 7-Zip додається:

```text
-p<password> -mhe=on
```

`-mhe=on` шифрує заголовки архіву, тобто приховує не тільки вміст файлів, а й список файлів всередині архіву.

Пароль у debug-логах маскується як:

```text
-p***
```

---

## Безпечне створення архівів

Архіви створюються за схемою:

```text
1. Створити тимчасовий архів у ARCHIV\TEMP\archive_*.mdz
2. Перевірити тимчасовий архів через 7za t
3. Якщо перевірка успішна — перенести у фінальну директорію
4. Якщо перевірка неуспішна — видалити тимчасовий файл
5. Створити або оновити SHA512
```

Це захищає від ситуації, коли після аварійного вимкнення живлення у фінальній директорії залишається битий `.mdz`.

Перевірити TEMP:

```powershell
Test-Path C:\LIMS\ARCHIV\TEMP
Get-ChildItem C:\LIMS\ARCHIV\TEMP -Force
```

Після успішної архівації `TEMP` зазвичай порожній. Якщо там лишився `archive_*.mdz`, архівація була перервана або завершилась помилкою до фінального перенесення.

---

## Slack

Режими Slack:

```powershell
SlackMode = "off"
SlackMode = "errors_only"
SlackMode = "all"
```

| Режим | Поведінка |
|---|---|
| `off` | Slack вимкнено |
| `errors_only` | Надсилати тільки критичні помилки |
| `all` | Надсилати всі підсумкові повідомлення |

Якщо `SlackMode` не дорівнює `off`, скрипт може запропонувати зберегти Slack webhook URL у Windows Credential Manager.

---

## Health-check

Health-check перевіряє:

- вільне місце на дисках;
- наявність останніх архівів;
- вік архівів;
- розмір архівів;
- SHA512-файли;
- валідність SHA512.

Окремий запуск:

```powershell
.\BRAVO_MAINTENANCE.ps1 -HealthCheckOnly
```

Приклад успішного результату:

```text
=== HEALTH-CHECK: ДИСКИ ТА АКТУАЛЬНІСТЬ АРХІВІВ ===
Health-check: C:\ вільне місце OK: 12.09 GB
Health-check: D:\ вільне місце OK: 90.28 GB
Health-check: E:\ вільне місце OK: 149.48 GB
Health-check: LIMS: архів актуальний і SHA512 валідний (...)
Health-check: BLOG: архів актуальний і SHA512 валідний (...)
Health-check: BRAVOEXCH: архів актуальний і SHA512 валідний (...)
Health-check: критичних проблем не виявлено
```

Пропустити health-check у звичайному запуску:

```powershell
.\BRAVO_MAINTENANCE.ps1 -SkipHealthCheck
```

---

## Progress-state після аварійного вимкнення

Скрипт зберігає progress-state у файл:

```text
C:\LIMS\ARCHIV\STATE\BRAVO_MAINTENANCE_STATE.json
```

У ньому зберігаються:

- `RunId`;
- статус запуску;
- поточний етап;
- завершені етапи;
- час старту/оновлення/завершення;
- metadata: імена архівів, логів, marker-файлів.

Показати стан:

```powershell
.\BRAVO_MAINTENANCE.ps1 -ShowProgressState
```

Скинути попередній state і почати новий запуск:

```powershell
.\BRAVO_MAINTENANCE.ps1 -ResetProgress
```

Проігнорувати state для поточного запуску:

```powershell
.\BRAVO_MAINTENANCE.ps1 -IgnoreProgress
```

Типові checkpoint-и:

```text
CHECK_FREE_SPACE
CREATE_DIRECTORIES
STOP_SERVICES
CHECK_MD_FILE_SIZES
RESTORE_MODEL
PROCESS_LOG_FILES
START_SERVICES
CLEANUP_OLD_DATA
ARCHIV_LIMS
```

Якщо живлення зникне під час виконання, наступний запуск зможе показати останню точку виконання.

---

## Windows Task Scheduler

Скрипт може створити задачу планувальника під окремим локальним користувачем, наприклад:

```text
LIMS-PCS\BRAVO_Scheduler
```

Користувач:

- створюється автоматично;
- приховується з екрана входу;
- отримує право запуску batch job;
- блокується для інтерактивного/RDP входу;
- може отримати доступ до Credential Manager через bootstrap.

Приклад встановлення задачі:

```powershell
.\BRAVO_MAINTENANCE.ps1 `
    -InstallScheduledTask `
    -TaskTime 23:00 `
    -TaskDaysOfWeek Sunday `
    -AddTaskUserToAdministrators
```

Зі скиданням пароля task-user:

```powershell
.\BRAVO_MAINTENANCE.ps1 `
    -InstallScheduledTask `
    -TaskTime 23:00 `
    -TaskDaysOfWeek Sunday `
    -AddTaskUserToAdministrators `
    -ResetTaskUserPassword
```

Якщо потрібно пропустити credential bootstrap:

```powershell
.\BRAVO_MAINTENANCE.ps1 `
    -InstallScheduledTask `
    -TaskTime 23:00 `
    -TaskDaysOfWeek Sunday `
    -SkipTaskUserCredentialBootstrap
```

Перевірити задачі:

```powershell
Get-ScheduledTask -TaskPath "\BRAVO\" |
    Format-Table TaskName, State, TaskPath
```

---

## Основні команди запуску

### Звичайний запуск

```powershell
.\BRAVO_MAINTENANCE.ps1
```

### Тільки health-check

```powershell
.\BRAVO_MAINTENANCE.ps1 -HealthCheckOnly
```

### Зберегти секрети

```powershell
.\BRAVO_MAINTENANCE.ps1 -SetupCredentials
```

### Показати progress-state

```powershell
.\BRAVO_MAINTENANCE.ps1 -ShowProgressState
```

### Скинути progress-state

```powershell
.\BRAVO_MAINTENANCE.ps1 -ResetProgress
```

### Пропустити Slack

```powershell
.\BRAVO_MAINTENANCE.ps1 -DisableAllSlack
```

### Увімкнути всі Slack-повідомлення

```powershell
.\BRAVO_MAINTENANCE.ps1 -EnableAllSlack
```

---

## Перевірка після змін

Синтаксис:

```powershell
$scriptText = Get-Content -LiteralPath .\BRAVO_MAINTENANCE.ps1 -Raw

try {
    [scriptblock]::Create($scriptText) | Out-Null
    "Syntax OK"
}
catch {
    $_.Exception.Message
}
```

Перевірка ключових функцій:

```powershell
Select-String -Path .\BRAVO_MAINTENANCE.ps1 -Pattern `
    "BRAVO_VERIFIED_ARCHIVE|New-BravoVerifiedArchive|ArchivePasswordEncryptHeaders|ArchiveTempDir|-mhe=on"
```

Health-check:

```powershell
.\BRAVO_MAINTENANCE.ps1 -HealthCheckOnly
```

Progress-state:

```powershell
.\BRAVO_MAINTENANCE.ps1 -ShowProgressState
```

---

## `.gitignore`

Рекомендовані виключення:

```gitignore
# Runtime data
/BAZA/
/BLOG/
/BRAVOEXCH/
/exchangAPI/
/LIMS/
/LOGS/
/STATE/
/TEMP/
/Trace/

# Local configs / secrets
/BRAVO.config.ps1
/ARCHIV_BRAVO.config.ps1
/BRAVO.Credentials.ps1

# Patch / backup files
/Apply-BRAVO-*.ps1
/*.bak_*
/*.tmp

# Generated files
/*.log
/*.csv
/*.mdz
/*.sha512
```

Не використовуйте бездумно:

```powershell
git add .
```

Краще додавати тільки потрібні файли:

```powershell
git add BRAVO_MAINTENANCE.ps1 BRAVO.config.example.ps1 README.md .gitignore
```

---

## Коміт змін

Перевірити статус:

```powershell
git status
```

Додати основні файли:

```powershell
git add BRAVO_MAINTENANCE.ps1 BRAVO.config.example.ps1 README.md
```

Перевірити staged-файли:

```powershell
git diff --cached --name-only
```

Коміт:

```powershell
git commit -m "Add verified archive creation and health checks"
```

Push:

```powershell
git push origin main
```

---

## Типові проблеми

### `ArchivePasswordEnabled = "on"`, але пароль не знайдено

Запустіть:

```powershell
.\BRAVO_MAINTENANCE.ps1 -SetupCredentials
```

Якщо задача запускається під `BRAVO_Scheduler`, перевстановіть задачу з credential bootstrap.

---

### Slack TLS error

Скрипт використовує `Invoke-BravoSlackWebhook` і `Set-BravoTlsProtocol`. Якщо TLS-помилка лишається, проблема може бути на рівні Windows/.NET/Schannel.

---

### `Health-check: BLOG: архів не знайдено`

Перевірте `HealthCheckArchiveCategories`. Для різних директорій має бути так:

```powershell
HealthCheckArchiveCategories = @(
    @{
        Name = "LIMS"
        Path = "{ROOT_LIMS}\ARCHIV\LIMS"
        Pattern = "{ArchivePrefix}_*.mdz"
    },
    @{
        Name = "BLOG"
        Path = "{ROOT_LIMS}\ARCHIV\BLOG"
        Pattern = "{ArchivePrefix}_blog_*.mdz"
    },
    @{
        Name = "BRAVOEXCH"
        Path = "{ROOT_LIMS}\ARCHIV\BRAVOEXCH"
        Pattern = "{ArchivePrefix}_bravoexch_*.mdz"
    }
)
```

---

### `Progress state exists and was not resumed`

Подивитися state:

```powershell
.\BRAVO_MAINTENANCE.ps1 -ShowProgressState
```

Почати чисто:

```powershell
.\BRAVO_MAINTENANCE.ps1 -ResetProgress
```

---

### `TEMP` не існує

Це нормально, якщо ще не запускалась реальна архівація. `-HealthCheckOnly` не створює архіви й не створює `TEMP`.

Створити вручну:

```powershell
New-Item -Path C:\LIMS\ARCHIV\TEMP -ItemType Directory -Force
```

---

## Рекомендована експлуатація

1. Налаштувати `BRAVO.config.ps1`.
2. Зберегти секрети через `-SetupCredentials`.
3. Перевірити `-HealthCheckOnly`.
4. Встановити scheduled task під `BRAVO_Scheduler`.
5. Після першого maintenance запуску перевірити:
   - `LOGS`;
   - `STATE`;
   - Slack;
   - актуальність архівів;
   - SHA512;
   - порожню `TEMP` після успішної архівації.
6. Не комітити runtime-файли та локальні конфіги.

---

## Статус реалізованих функцій

| Функція | Статус |
|---|---|
| Windows Credential Manager | Реалізовано |
| Dedicated scheduler user | Реалізовано |
| Slack TLS-safe sender | Реалізовано |
| Progress-state | Реалізовано |
| Health-check архівів | Реалізовано |
| SHA512 validation | Реалізовано |
| Verified temp archive | Реалізовано |
| `-mhe=on` encrypted headers | Реалізовано |
| Network backup | Заплановано |
| SFTP upload | Заплановано |
| ArchiveOnly для LIMS/BLOG/BRAVOEXCH | Заплановано |

---

## Примітка з безпеки

Не зберігайте паролі, webhook URL та інші секрети в Git. Для цього використовуйте Windows Credential Manager.

Локальні файли, які не можна комітити:

```text
BRAVO.config.ps1
ARCHIV_BRAVO.config.ps1
BRAVO.Credentials.ps1
*.mdz
*.sha512
LOGS\
STATE\
TEMP\
Trace\
```
