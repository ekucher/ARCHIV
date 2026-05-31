# Stage 5.1 — Закриття progress state при помилці перевірки місця

## Гілка

stage5-progress-state-failure-handling

## Коміти

- f815415 — Close progress state on free space check failure

## Коротко

У цьому етапі покращено аварійне завершення maintenance-скрипта BRAVO під час помилки перевірки вільного місця.

Після ініціалізації progress state скрипт виконує перевірку вільного місця через Check-FreeSpace. Якщо ця перевірка повертала помилку, скрипт завершувався через exit 1 без явного закриття progress state і без явного звільнення mutex.

Цей етап закриває саме цей аварійний шлях.

## Що змінено

### 1. Закриття progress state при помилці Check-FreeSpace

У блоці помилки перевірки вільного місця перед командою:

exit 1

додано виклик:

Close-BravoProgressState -Status "CompletedWithErrors"

Тепер progress state не залишається у статусі Running після критичної помилки перевірки місця.

### 2. Звільнення runtime mutex перед аварійним виходом

У цьому ж блоці перед exit 1 додано:

Release-BravoMaintenanceMutex

Тепер Global\\BRAVO_MAINTENANCE звільняється навіть у випадку помилки Check-FreeSpace.

## Навіщо це потрібно

Без цієї правки аварійне завершення після Initialize-BravoProgressState могло залишити progress state у стані Running.

Це могло створювати плутанину при наступному запуску або при перегляді стану виконання через ShowProgressState.

Після зміни цей конкретний аварійний шлях завершується контрольовано:

- progress state отримує статус CompletedWithErrors;
- mutex звільняється;
- скрипт завершується з exit 1.

## Перевірка

Локально виконано збірку монолітного runtime-скрипта:

Build-BRAVO-Monolith.ps1 -Clean -CreateSha512

Результат:

Build completed successfully.
Syntax OK: dist\\BRAVO_MAINTENANCE.ps1
SHA512 created: dist\\BRAVO_MAINTENANCE.ps1.sha512

## Змінені файли

- src/99-Main.ps1

## Примітки

Зміна точкова: у блоці помилки Check-FreeSpace додано два рядки перед exit 1.

Тимчасові patch-скрипти та backup-директорії не входять у коміти.
