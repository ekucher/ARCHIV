# Stage 4 — Безпечніше завершення ShowProgressState

## Гілка

stage4-show-progress-mutex-release

## Коміти

- faa5ad4 — Release mutex before show progress exit

## Коротко

У цьому етапі покращено ранній вихід maintenance-скрипта BRAVO в режимі ShowProgressState.

Після попередніх етапів основний фінальний шлях та HealthCheckOnly уже звільняли runtime mutex перед завершенням процесу. Але режим ShowProgressState має окремий ранній вихід зі скрипта, який виконується до основного runtime-процесу.

Цей етап закриває саме цей ранній шлях завершення.

## Що змінено

### 1. Звільнення mutex перед ShowProgressState exit

У блоці ShowProgressState перед командою:

exit 0

додано виклик:

Release-BravoMaintenanceMutex

Тепер режим ShowProgressState також явно звільняє Global\\BRAVO_MAINTENANCE перед виходом.

## Навіщо це потрібно

Без цієї правки режим ShowProgressState міг завершити процес раніше основного фінального блоку, де вже було додано звільнення mutex.

Після зміни штатні ранні виходи ShowProgressState та HealthCheckOnly, а також основний фінальний шлях, звільняють mutex явно.

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

Зміна мінімальна: додано один рядок у ShowProgressState-гілці.

Тимчасові patch-скрипти та backup-директорії не входять у коміти.
