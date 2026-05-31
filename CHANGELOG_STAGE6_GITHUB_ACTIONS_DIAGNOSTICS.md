# Stage 6 — Діагностика GitHub Actions для syntax/build перевірок

## Гілка

stage6-github-actions-ci-cleanup

## Коміти

- d6541d8 — Improve GitHub Actions build diagnostics

## Коротко

У цьому етапі покращено GitHub Actions workflow для перевірки PowerShell-синтаксису та збірки монолітного BRAVO maintenance-скрипта.

Runtime-логіку BRAVO не змінено. Зміни стосуються тільки CI/CD діагностики.

## Що змінено

Оновлено два workflow:

- .github/workflows/powershell-syntax.yml
- .github/workflows/bravo-build-validation.yml

Після checkout додано окремий diagnostic step, який показує:

- поточну директорію runner-а;
- Git HEAD;
- список файлів у корені репозиторію;
- наявність .git;
- наявність Build-BRAVO-Monolith.ps1;
- наявність src/BRAVO.build.json.

Також покращено текст помилки, якщо Build-BRAVO-Monolith.ps1 не знайдено.

## Навіщо це потрібно

Раніше при помилці GitHub Actions міг показувати лише загальне повідомлення, що Build-BRAVO-Monolith.ps1 не знайдено.

Після цієї зміни в логах буде видно, з якої директорії запускається workflow, який commit перевіряється і які файли реально присутні після checkout.

Це спрощує діагностику проблем із робочою директорією, checkout або структурою репозиторію.

## Додатково

У powershell-syntax.yml actions/checkout приведено до v4, як і в bravo-build-validation.yml.

## Змінені файли

- .github/workflows/powershell-syntax.yml
- .github/workflows/bravo-build-validation.yml

## Примітки

Зміни не впливають на runtime-скрипт BRAVO.

Тимчасові patch-скрипти та backup-директорії не входять у коміти.
