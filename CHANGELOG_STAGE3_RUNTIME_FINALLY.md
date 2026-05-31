# Stage 3 — Безпечніше завершення runtime

## Гілка

stage3-runtime-finally

## Коміти

- 4c81e55 — Release mutex before health check exit

## Коротко

У цьому етапі покращено завершення maintenance-скрипта BRAVO у режимі HealthCheckOnly.

Після попередніх етапів основний фінальний шлях уже звільняв runtime mutex перед завершенням процесу. Але режим HealthCheckOnly має окремий ранній вихід зі скрипта, який завершує виконання до основного фінального блоку.

Цей етап закриває саме цей ранній шлях завершення.

## Що змінено

### 1. Звільнення mutex перед HealthCheckOnly exit

У блоці HealthCheckOnly перед командою:

exit $healthExitCode

додано виклик:

Release-BravoMaintenanceMutex

Тепер запуск у режимі HealthCheckOnly також явно звільняє Global\\BRAVO_MAINTENANCE перед виходом.

## Навіщо це потрібно

Без цієї правки режим HealthCheckOnly міг завершити процес раніше основного фінального блоку, де вже було додано звільнення mutex.

Після зміни всі штатні шляхи завершення, які проходять через фінальний блок або HealthCheckOnly, звільняють mutex явно.

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

Зміна мінімальна: додано один рядок у HealthCheckOnly-гілці.

Тимчасові patch-скрипти та backup-директорії не входять у коміти.
