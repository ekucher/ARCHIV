##########
# BravoSoft / VetOffice
# ARCHIV_VETOFFICE.config.example.ps1
#
# Конфігурація для ARCHIV_VETOFFICE.ps1
# Версія конфігурації: 2.5.1
# Це приклад конфігурації. Скопіюйте його в ARCHIV_VETOFFICE.config.ps1 і внесіть свої значення.
##########

# =============================================
# 1. ОСНОВНІ НАЛАШТУВАННЯ
# =============================================

# Рівень логування:
# DEBUG   - максимально детально
# INFO    - стандартний режим
# WARNING - тільки попередження та помилки
# ERROR   - тільки помилки
# SUCCESS - тільки успішні повідомлення
$global:LogLevel = 'INFO'

# Префікс імен архівів.
$global:archivePrefix = 'vetcontrol_dev_pnmgu_v2508'

# =============================================
# 2. ШЛЯХИ
# =============================================

# Кореневий каталог VetOffice.
$global:rootPath = 'E:\VetOffice'

# Основний каталог архівів.
$global:archivPath = Join-Path $global:rootPath 'ARCHIV'

# Каталог інструментів: 7za.exe, WinSCP.com.
$global:toolsPath = Join-Path $global:archivPath 'Tools'

# Каталог логів, JSON-звітів і history.json.
$global:logPath = Join-Path $global:archivPath 'LOGS'

# Опційний прямий шлях до WinSCP.com.
# Якщо порожньо, скрипт шукає WinSCP.com у Tools або в системі.
$global:winSCPPath = ''

# =============================================
# 3. ДЖЕРЕЛА ТА КАТАЛОГИ АРХІВІВ
# =============================================

$global:sourcePaths = @{
    # Вміст каталогу Model.
    Model = Join-Path $global:rootPath "Model\*"

    # Вміст каталогу BLOG.
    Blog  = Join-Path $global:rootPath "BLOG\*"
}

$global:archiveDirs = @{
    # Локальний каталог архівів VETOFFICE / Model.
    Model = Join-Path $global:archivPath "VETOFFICE"

    # Локальний каталог архівів BLOG.
    Blog  = Join-Path $global:archivPath "BLOG"
}

# true  - компонент вимкнений
# false - компонент увімкнений
$global:excludeComponents = @{
    VETOFFICE    = $false
    Blog         = $false
    BAZA         = $true
    BAZA_Network = $true
}

# =============================================
# 4. 7-ZIP ТА ПАРАМЕТРИ АРХІВАЦІЇ
# =============================================

# Параметри створення архіву 7-Zip.
# Типово:
# a             - створити архів
# -mmt          - багатопоточність
# -mx5          - рівень стиснення 5
# -r            - рекурсивно
# -y            - автоматично Yes
# -ssw          - архівувати відкриті файли
# -scrcSHA512   - SHA512 для 7-Zip
# -bb0          - мінімальний вивід 7-Zip
# -aoa          - overwrite all при розпакуванні
# -pPASSWORD    - пароль архіву, якщо використовується
$global:archiveParams = 'a -mmt -mx5 -r -y -ssw -scrcSHA512 -bb0 -aoa'

# Брати пароль архіву з Windows Credential Manager.
# Команда для збереження:
# cmdkey /generic:ARCHIV_VETOFFICE_ARCHIVE_PASSWORD /user:archive /pass:ВашПароль
$global:enableArchivePassword = $false
$global:archivePasswordCredentialTarget = 'ARCHIV_VETOFFICE_ARCHIVE_PASSWORD'

# =============================================
# 5. ПЕРЕВІРКА АРХІВІВ
# =============================================

# Перевіряти архів після створення через 7za.exe t.
$global:enableArchiveIntegrityTest = $true

# Перевіряти, що архів не має підозріло малого розміру.
$global:enableArchiveSizeValidation = $true

# Мінімальний допустимий розмір архіву, MB.
# 0 = не перевіряти.
$global:minimumArchiveSizeMB = 1

# Мінімальна частка архіву від розміру джерела у відсотках.
# 0.1 = 0.1%.
# 0 = не перевіряти.
$global:minimumArchivePercentOfSource = 0.1

# Опційне тестове відновлення архіву у тимчасову папку.
$global:enableArchiveTestRestore = $false

# Тимчасовий каталог для Test Restore.
$global:archiveTestRestoreTempPath = "$env:TEMP\ARCHIV_VETOFFICE_TEST_RESTORE"

# =============================================
# 6. ПЕРЕВІРКА ВІЛЬНОГО МІСЦЯ
# =============================================

# Мінімальний резерв вільного місця, GB.
$global:freeSpaceReserveGB = 5

# Alias для сумісності зі старішою логікою.
$global:archiveMinFreeSpaceGB = 5

# Множник до розміру джерела.
$global:archiveSpaceMultiplier = 1.2

# Попередження при залишку менше N GB.
$global:diskHealthWarningGB = 20

# Помилка при залишку менше N GB.
$global:diskHealthCriticalGB = 10

# =============================================
# 7. RETENTION
# =============================================

# Кількість лог-файлів, які залишати.
$global:logRetentionDays = 31

# Старий параметр кількості версій архівів.
# Залишений для сумісності та як default для archiveRetentionKeepCount.
$global:archiveVersions = 31

# Увімкнути видалення старих архівів і відповідних .sha512.
$global:enableArchiveDeletion = $true

# Скільки останніх комплектів archive.mdz + archive.mdz.sha512 залишати.
$global:archiveRetentionKeepCount = 31

# Додаткове обмеження за віком у днях.
# 0 = не використовувати обмеження за віком.
$global:archiveRetentionKeepDays = 0

# =============================================
# 8. SFTP
# =============================================

# Увімкнути завантаження архівів і .sha512 на SFTP.
$global:enableSFTPUpload = $false
# Перевіряти розмір файлу на SFTP після завантаження.
# true  - після upload виконується stat і порівнюється розмір локального та віддаленого файлу
# false - перевірка після upload не виконується
$global:enableSftpUploadVerify = $true

# Увімкнути retention на SFTP.
# true  - старі архіви та .sha512 видаляються на SFTP
# false - SFTP retention не виконується
$global:enableSftpRetention = $false

# Скільки останніх комплектів archive.mdz + archive.mdz.sha512 залишати на SFTP.
$global:sftpRetentionKeepCount = 31

# Логін SFTP.
$global:Login = 'sftp_user'

# Пароль SFTP.
# Рекомендовано зберігати у Windows Credential Manager, а тут залишати fallback.
$global:Password = ''

# Target у Windows Credential Manager для SFTP-пароля.
# cmdkey /generic:ARCHIV_VETOFFICE_SFTP_PASSWORD /user:sftp /pass:ВашПароль
$global:sftpPasswordCredentialTarget = 'ARCHIV_VETOFFICE_SFTP_PASSWORD'

# URL SFTP.
# Якщо URL без user:password, скрипт підставить Login/Password автоматично.
$global:sftpUrl = 'sftp://backup.example.com/'

# HostKey WinSCP.
$global:sftpHostKey = 'ssh-ed25519 255 SHA256:CHANGE_ME'

# Віддалені каталоги.
$global:sftpDirectories = @{
    Model = 'archiv'
    Blog  = 'blog'
}

# =============================================
# 9. МЕРЕЖЕВЕ КОПІЮВАННЯ / SAMBA
# =============================================

# Увімкнути копіювання архівів і .sha512 у мережеву папку.
$global:enableNetworkCopy = $false

# Базовий UNC-шлях.
$global:NetworkPath = '\\SERVER\Backup\VetOffice'

$global:networkCopyConfig = @{
    Enabled                  = $global:enableNetworkCopy
    NetworkPath              = $global:NetworkPath
    Username                 = ''

    # Fallback-пароль. Краще використовувати Credential Manager.
    Password                 = ''

    # Target у Windows Credential Manager для пароля мережевої папки.
    PasswordCredentialTarget = 'ARCHIV_VETOFFICE_NETWORK_PASSWORD'

    # Кількість спроб підключення.
    MaxRetries               = 3

    # Затримка між спробами, секунди.
    RetryDelay               = 5
}

# =============================================
# 10. BAZA
# =============================================

$global:bazaPaths = @{
    Source              = Join-Path $global:rootPath "BAZA"
    Destination_Local   = Join-Path $global:archivPath "BAZA"
    Destination_Network = Join-Path $global:NetworkPath "BAZA"
}

# =============================================
# 11. СПОВІЩЕННЯ
# =============================================

# Поки використовується для формування плану сповіщень у JSON/логах.
$global:enableTelegramNotify = $false
$global:enableEmailNotify = $false

# Коли формувати сповіщення.
$global:enableNotifyOnSuccess = $false
$global:enableNotifyOnWarning = $true
$global:enableNotifyOnError = $true