# ARCHIV_VETOFFICE

Система резервного копіювання для VetOffice з підтримкою архівації 7-Zip, SHA512-перевірки, контролю вільного місця, JSON-звітів та автоматичного retention архівів.

## Основні можливості

- Архівація каталогів VetOffice та Blog
- Стиснення за допомогою 7-Zip
- Захист архівів паролем
- Автоматичне створення SHA512-хешів
- Перевірка цілісності архівів
- Перевірка контрольних сум SHA512
- Контроль доступного місця на диску
- JSON-звіти для інтеграції та моніторингу
- Історія запусків
- Режим DRY-RUN
- Детальне логування
- Автоматичне очищення старих логів
- Retention політика для архівів та SHA512-файлів

---

## Версія 2.3

### Нове у релізі

#### Archive Retention

Додано автоматичне керування життєвим циклом резервних копій.

Можливості:

- зберігання лише останніх N архівів;
- автоматичне видалення відповідних SHA512-файлів;
- підтримка DRY-RUN режиму;
- статистика retention у JSON-звіті;
- обробка orphan SHA512-файлів;
- окрема політика для кожного типу архівів.

Приклад:

```powershell
$enableArchiveDeletion      = $true
$archiveRetentionKeepCount  = 31
$archiveRetentionKeepDays   = 0
```

---

#### Контроль вільного місця

Наприкінці роботи виконується оцінка стану диска архівів.

Результати:

- OK
- WARNING
- CRITICAL

Приклад налаштувань:

```powershell
$diskHealthWarningGB = 20
$diskHealthCriticalGB = 10
```

---

#### План сповіщень

Додано механізм формування Notification Plan.

Враховуються:

- помилки архівації;
- помилки SHA512;
- критично малий вільний простір;
- результати retention.

Статус записується у JSON-звіт.

---

#### Розширений JSON-звіт

JSON тепер містить додаткові розділи:

```json
{
  "retention": {},
  "disk_health": {},
  "notifications": {}
}
```

---

## Налаштування

Основні параметри:

```powershell
$archiveVersions = 31

$enableArchiveDeletion = $true
$archiveRetentionKeepCount = 31
$archiveRetentionKeepDays = 0

$diskHealthWarningGB = 20
$diskHealthCriticalGB = 10

$enableArchiveIntegrityTest = $true
```

---

## Режим DRY-RUN

Для перевірки роботи без створення або видалення файлів:

```powershell
.\ARCHIV_VETOFFICE.ps1 -DryRun
```

У цьому режимі:

- архіви не створюються;
- SHA512 не генеруються;
- файли не видаляються;
- показується повний план виконання.

---

## Приклад результату

```text
=== RETENTION АРХІВІВ ===

--- BLOG ---
[INFO] Архівів: 31 | SHA512: 31 | Ліміт: 31
[INFO] Видалення не потрібне

--- VETOFFICE ---
[INFO] Архівів: 31 | SHA512: 28 | Ліміт: 31
[INFO] Видалення не потрібне
```

---

## Структура проекту

```text
ARCHIV/
├── ARCHIV_VETOFFICE.ps1
├── ARCHIV_VETOFFICE.config.ps1
├── ARCHIV_VETOFFICE.config.example.ps1
├── BLOG/
├── VETOFFICE/
└── LOGS/
```

---

## Історія версій

### v2.3

- Archive Retention
- Disk Health Monitoring
- Notification Plan
- Extended JSON Reports
- Compact Retention Output

### v2.2

- SHA512 Verification
- 7-Zip Archive Integrity Test
- Backup Health Status

### v2.1

- Initial stable release

# ARCHIV_VETOFFICE v2.4

## Release Date

2026-05-30

## What's New

### SFTP Upload Support Stabilized

Повністю перероблено та стабілізовано механізм завантаження резервних копій на SFTP-сервер через WinSCP.

#### Виправлено

* Коректне визначення шляху до `WinSCP.com`
* Покращена обробка параметра `RepositorySFTPUrl`
* Виправлено розбір URL з символом `@` у логіні
* Додано автоматичне формування StorageBox host:

  * `u363066` → `u363066.your-storagebox.de`
* Виправлено створення команди `open` для WinSCP
* Додано підтримку парольної автентифікації
* Вимкнено вплив локального SSH Agent (Pageant/OpenSSH Agent)
* Покращено обробку помилок підключення
* Додано детальне логування WinSCP stdout/stderr
* Виправлено визначення статусів:

  * `success`
  * `connection_failed`
  * `upload_failed`
  * `disabled`

#### Автоматичне створення каталогів

Під час першого запуску скрипт автоматично створює віддалені каталоги:

* `/archiv`
* `/blog`

Якщо каталог уже існує, завантаження продовжується без помилки.

Використовується схема:

```winscp
option batch continue
mkdir /archiv
option batch abort
cd /archiv
put "file.mdz"
```

#### Покращена діагностика

У лог тепер записуються:

* помилки підключення;
* помилки автентифікації;
* помилки завантаження;
* повідомлення WinSCP;
* коди помилок сервера;
* текстові повідомлення SFTP-сервера.

Приклад:

```text
[ERROR] WinSCP upload stdout:
Помилка зміни теки на '/archiv'
Код помилки: 2
No such file
```

---

### JSON Reporting Improvements

Виправлено формування підсумкового статусу SFTP у JSON-звітах.

Раніше могли з'являтися некоректні статуси:

```json
"sftp_status": "disabled"
```

або

```json
"sftp_status": "connection_failed"
```

навіть при фактичному виконанні завантаження.

Тепер статус відповідає реальному результату операції.

---

### Backup Workflow

Поточна послідовність роботи:

1. Архівація даних.
2. Перевірка архіву через 7-Zip.
3. Створення SHA512.
4. Перевірка SHA512.
5. Перевірка конфігурації SFTP.
6. Підключення до SFTP.
7. Створення каталогів за потреби.
8. Завантаження архівів.
9. Завантаження SHA512.
10. Оновлення JSON-звіту.
11. Оновлення історії запусків.
12. Retention локальних архівів.
13. Очищення старих логів.

---

## Tested

Успішно протестовано:

* Створення архівів VETOFFICE
* Створення архівів BLOG
* Перевірку архівів 7-Zip
* Генерацію SHA512
* Перевірку SHA512
* Підключення до Hetzner StorageBox SFTP
* Автоматичне створення каталогів
* Повторне завантаження у вже існуючі каталоги
* Завантаження архівів
* Завантаження SHA512
* JSON-звіти
* Історію запусків
* Retention локальних резервних копій

---

## Result

ARCHIV_VETOFFICE v2.4 вважається стабільним релізом для продуктивного використання.
