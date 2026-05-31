# Stage 5.2 — Звільнення mutex при ранніх runtime-помилках

## Гілка

stage5-runtime-early-error-cleanup

## Коміти

- 7624a52 — Release mutex before early setup error exits

## Коротко

У цьому етапі покращено завершення maintenance-скрипта BRAVO у ранніх аварійних шляхах, які виконуються після створення runtime mutex, але до ініціалізації progress state.

Ці гілки завершення не повинні закривати progress state, бо він ще не створений. Але вони вже повинні звільняти Global\BRAVO_MAINTENANCE, оскільки mutex на цей момент уже захоплений.

## Що змінено

Перед exit 1 додано виклик:

Release-BravoMaintenanceMutex

у трьох ранніх аварійних блоках:

1. помилка перевірки версії ОС;
2. запуск скрипта не з папки ARCHIV;
3. помилка створення директорії логів.

## Навіщо це потрібно

Без цієї правки ранній exit 1 після створення mutex міг завершити процес без явного звільнення Global\BRAVO_MAINTENANCE.

Після зміни ці аварійні сценарії завершуються контрольовано:

- помилка виводиться користувачу;
- mutex звільняється;
- скрипт завершується з exit 1.

## Чому не додається Close-BravoProgressState

У цих трьох блоках Initialize-BravoProgressState ще не виконувався, тому progress state ще не існує.

Через це додано тільки Release-BravoMaintenanceMutex, без Close-BravoProgressState.

## Перевірка

Локально виконано:

.\Build-BRAVO-Monolith.ps1 -Clean -CreateSha512

Результат:

Build completed successfully.
Syntax OK: dist\BRAVO_MAINTENANCE.ps1
SHA512 created: dist\BRAVO_MAINTENANCE.ps1.sha512

## Змінені файли

- src/99-Main.ps1

## Примітки

Зміна точкова: додано три виклики Release-BravoMaintenanceMutex перед ранніми exit 1.

Тимчасові patch-скрипти та backup-директорії не входять у коміти.
