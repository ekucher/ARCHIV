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
