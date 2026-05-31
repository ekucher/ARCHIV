# Stage 7 — Зменшення дублювання GitHub Actions workflow

## Гілка

stage7-ci-workflow-deduplication

## Коміти

- 3396c3a — Deduplicate GitHub Actions build workflow

## Коротко

У цьому етапі зменшено дублювання між двома GitHub Actions workflow.

powershell-syntax.yml залишено легким workflow для перевірки root-моноліту BRAVO_MAINTENANCE.ps1, якщо такий файл є в корені репозиторію.

Повна збірка моноліту, перевірка src/*.ps1 і перевірка згенерованого dist/BRAVO_MAINTENANCE.ps1 залишені у bravo-build-validation.yml.

## Що змінено

У .github/workflows/powershell-syntax.yml:

- job перейменовано з syntax-and-build на root-monolith-syntax;
- назву job змінено на Validate root PowerShell monolith syntax;
- прибрано крок Build generated monolith;
- прибрано крок Check generated monolith syntax;
- прибрано крок Verify generated files.

## Навіщо це потрібно

До цієї зміни powershell-syntax.yml і bravo-build-validation.yml частково виконували одну й ту саму роботу: збирали моноліт і перевіряли згенерований файл.

Після зміни відповідальність workflow розділено чіткіше:

- powershell-syntax.yml — легка перевірка root-моноліту, якщо він існує;
- bravo-build-validation.yml — основна build-перевірка, syntax check src/*.ps1 і перевірка generated output.

Це зменшує дублювання CI, спрощує логи та робить призначення workflow зрозумілішим.

## Що не змінювалось

- Runtime-код BRAVO не змінювався;
- Build-BRAVO-Monolith.ps1 не змінювався;
- bravo-build-validation.yml не змінювався у цьому етапі.

## Змінені файли

- .github/workflows/powershell-syntax.yml

## Примітки

Зміна стосується тільки CI/CD конфігурації.

Тимчасові patch-скрипти та backup-директорії не входять у коміти.
