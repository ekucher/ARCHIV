###########
# BravoSoft / VetOffice
# ARCHIV_VETOFFICE.config.example.ps1
#
# Приклад конфігурації для ARCHIV_VETOFFICE.ps1
#
# Як використовувати:
#   1. Скопіюйте цей файл у ARCHIV_VETOFFICE.config.ps1
#   2. Відредагуйте шляхи, назву архіву та параметри
#   3. Не комітьте реальний ARCHIV_VETOFFICE.config.ps1, якщо там є паролі
##########

# =============================================
# ОСНОВНІ ШЛЯХИ
# =============================================

# Коренева папка VetOffice
$rootPath = "E:\VetOffice"

# Папка зі службовими утилітами
# Очікуються:
#   Tools\7za.exe
#   Tools\WinSCP.com
#   Tools\WinSCP.exe
$toolsPath = Join-Path $PSScriptRoot "Tools"

# Папка логів
$logPath = Join-Path $PSScriptRoot "LOGS"

# Коренева папка архівів
$archivPath = $PSScriptRoot

# =============================================
# ДЖЕРЕЛА ДАНИХ
# =============================================

$sourcePaths = @{
    # Основна папка VetOffice / Model
    Model = Join-Path $rootPath "VETOFFICE"

    # Папка BLOG, якщо використовується
    Blog  = Join-Path $rootPath "BLOG"
}

# =============================================
# ПАПКИ ПРИЗНАЧЕННЯ ДЛЯ АРХІВІВ
# =============================================

$archiveDirs = @{
    # Архіви основної бази / Model / VetOffice
    Model = Join-Path $archivPath "VETOFFICE"

    # Архіви BLOG
    Blog  = Join-Path $archivPath "BLOG"
}

# =============================================
# НАЗВИ ТА ПАРАМЕТРИ АРХІВАЦІЇ
# =============================================

# Префікс імені архівів.
# Фінальне ім'я буде приблизно:
#   vetcontrol_dev_pnmgu_v2508_20260529_2318.mdz
#   vetcontrol_dev_pnmgu_v2508_blog_20260529_2318.mdz
$archivePrefix = "vetcontrol_dev_pnmgu_v2508"

# Параметри 7-Zip.
# Рекомендовано залишити розширення .mdz у назві архіву, а формат архіву явно задати через -tzip або інший потрібний формат.
#
# Приклад ZIP-сумісного архіву:
$archiveParams = "a -mmt -mx9 -r -y -ssw -scrcSHA512 -bb0 -aoa"

# Пароль архiву з Windows Credential Manager.
# Зберегти:
#   cmdkey /generic:ARCHIV_VETOFFICE_ARCHIVE_PASSWORD /user:archive /pass:ВашПароль
$enableArchivePassword = $true
$archivePasswordCredentialTarget = "ARCHIV_VETOFFICE_ARCHIVE_PASSWORD"

# Кількість останніх архівів / hash-файлів, які залишати при очищенні
$archiveVersions = 7

# =============================================
# RETENTION АРХІВІВ
# =============================================

# Увімкнути очищення старих архівів.
# true  - старі архіви та відповідні .sha512 будуть видалятися
# false - архіви не видаляються
# Комплект = archive.mdz + archive.mdz.sha512
$archiveRetentionKeepCount = 31
# 0 = не використовувати обмеження за віком, тільки кількість.
$archiveRetentionKeepDays = 0
$logRetentionDays = 31

# Увімкнути видалення старих архівів
$enableArchiveDeletion = $true
# ПЕРЕВІРКА АРХІВІВ
# =============================================

# Перевірка архіву після створення через 7-Zip:
#   7za.exe t archive.mdz -p*****
#
# Якщо архів захищено паролем, скрипт використовує той самий пароль,
# що й для створення архіву.
#
# true  - перевіряти архів після створення
# false - не перевіряти
#
# Рекомендація:
#   Для щоденного бойового запуску можна встановити true.
#   Якщо перевірка зависає або потрібно швидке тестування — залишити false.
$enableArchiveIntegrityTest = $false

# =============================================
# ПЕРЕВІРКА ВІЛЬНОГО МІСЦЯ
# =============================================

# Мінімальний резерв вільного місця на диску архіву, GB
$freeSpaceReserveGB = 5

# Множник до розміру джерела.
# Наприклад, якщо джерело 10 GB і множник 1.2, потрібно мінімум 12 GB.
# Фактично використовується max($freeSpaceReserveGB, sourceSize * multiplier).
$archiveSpaceMultiplier = 1.2

# =============================================
# КОМПОНЕНТИ, ЯКІ МОЖНА ВИМКНУТИ
# =============================================

$excludeComponents = @{
    # Основна архівація VetOffice / Model
    VETOFFICE    = $false

    # Архівація BLOG
    Blog         = $false

    # Локальна синхронізація BAZA
    BAZA         = $true

    # Мережева синхронізація BAZA
    BAZA_Network = $true
}

# =============================================
# BAZA / СИНХРОНІЗАЦІЯ
# =============================================

$bazaPaths = @{
    Source              = Join-Path $rootPath "BAZA"
    Destination_Local   = Join-Path $archivPath "BAZA"
    Destination_Network = "\\SERVER\Backup\VetOffice\BAZA"
}

# =============================================
# SFTP
# =============================================

# Увімкнути завантаження архівів і hash-файлів на SFTP
$enableSFTPUpload = $false

# Облікові дані SFTP.
# Не зберігайте реальні паролі у публічному репозиторії.
$Login = "sftp_user"
# Пароль SFTP з Windows Credential Manager.
# Зберегти:
#   cmdkey /generic:ARCHIV_VETOFFICE_SFTP_PASSWORD /user:sftp /pass:ВашПароль
$sftpPasswordCredentialTarget = "ARCHIV_VETOFFICE_SFTP_PASSWORD"
$Password = ""

# URL у форматі WinSCP, наприклад:
#   sftp://backup.example.com/
$sftpUrl = "sftp://backup.example.com/"

# HostKey WinSCP.
# Отримайте актуальне значення при першому підключенні або з налаштувань сервера.
$sftpHostKey = "ssh-ed25519 255 SHA256:CHANGE_ME"

# Віддалені каталоги SFTP
$sftpDirectories = @{
    Model = "/backup/VetOffice/Model"
    BLOG  = "/backup/VetOffice/BLOG"
}

# =============================================
# КОПІЮВАННЯ В МЕРЕЖЕВУ ПАПКУ
# =============================================

# Увімкнути копіювання архівів у мережеву папку
$enableNetworkCopy = $false

$networkCopyConfig = @{
    NetworkPath = "\\SERVER\Backup\VetOffice"
    Username    = ""
    # Пароль мережевої папки з Windows Credential Manager.
    # Зберегти:
    #   cmdkey /generic:ARCHIV_VETOFFICE_NETWORK_PASSWORD /user:network /pass:ВашПароль
    PasswordCredentialTarget = "ARCHIV_VETOFFICE_NETWORK_PASSWORD"
    Password    = ""
    MaxRetries  = 3
    RetryDelay  = 10
}

# =============================================
# ЛОГУВАННЯ ТА ВИВІД
# =============================================

# Рівень логування:
#   DEBUG   - максимально детально
#   INFO    - стандартний режим
#   WARNING - тільки попередження і помилки
#   ERROR   - тільки помилки
$global:LogLevel = "INFO"

# Показувати додаткову інформацію про систему
$showSystemInfo = $false
$showHardwareInfo = $false
$showPerformanceInfo = $false

# Режим сумісності, якщо потрібен для старих середовищ
$compatibilityMode = $false

# =============================================
# HEALTH-CHECK ВІЛЬНОГО МІСЦЯ
# =============================================

# WARNING, якщо після виконання вільного місця менше цього значення.
$diskHealthWarningGB = 20

# ERROR, якщо після виконання вільного місця менше цього значення.
$diskHealthCriticalGB = 10
# =============================================
# СПОВІЩЕННЯ
# =============================================

# Каркас для майбутніх сповіщень.
# У v2.3 поки формується тільки план сповіщення у JSON/логах.
$enableTelegramNotify = $false
$enableEmailNotify = $false

# Коли формувати сповіщення.
$enableNotifyOnSuccess = $false
$enableNotifyOnWarning = $true
$enableNotifyOnError = $true

# НАЛАШТУВАННЯ ПЕРЕВIРКИ НАДIЙНОСТI АРХIВIВ v2.5
$global:enableArchiveSizeValidation = $true        # Перевiряти, що архiв не має пiдозрiло малого розмiру
$global:minimumArchiveSizeMB = 1                   # Мiнiмальний розмiр архiву в MB; 0 = не перевiряти
$global:minimumArchivePercentOfSource = 0.1        # Мiнiмальна частка архiву вiд розмiру джерела у %; 0 = не перевiряти
$global:enableArchiveTestRestore = $false          # Виконувати тестове вiдновлення архiву у тимчасовий каталог
$global:archiveTestRestoreTempPath = "$env:TEMP\ARCHIV_VETOFFICE_TEST_RESTORE"
