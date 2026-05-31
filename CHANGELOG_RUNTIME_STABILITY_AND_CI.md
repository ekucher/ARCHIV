# Runtime Stability and CI Changelog Index

## Призначення

Цей документ є зведеним індексом змін, виконаних у серії етапів стабілізації runtime-поведінки BRAVO maintenance-скрипта та впорядкування GitHub Actions CI.

Детальні changelog-файли окремих етапів залишаються в репозиторії як історія робіт. Цей файл потрібен як коротка карта: що було зроблено, де шукати деталі і який поточний статус.

## Поточний статус

- Runtime cleanup: завершено.
- Progress state failure handling: завершено.
- GitHub Actions diagnostics: завершено.
- CI workflow deduplication: завершено.
- Manual CI verification: BRAVO Build Validation на main пройшов успішно.

## Зведення етапів

| Stage | Тема | PR / Commit | Основні файли | Статус | Деталі |
| --- | --- | --- | --- | --- | --- |
| Stage 1 | Runtime stability safeguards | PR #41 / c1249af, 2618132 | src/99-Main.ps1 | Done | CHANGELOG_STAGE1_RUNTIME_STABILITY.md |
| Stage 3 | Runtime finalization cleanup | PR #42 / 4c81e55, badf95e | src/99-Main.ps1 | Done | CHANGELOG_STAGE3_RUNTIME_FINALLY.md |
| Stage 4 | ShowProgressState mutex release | PR #43 / faa5ad4, 6f0d005 | src/99-Main.ps1 | Done | CHANGELOG_STAGE4_SHOW_PROGRESS_MUTEX_RELEASE.md |
| Stage 5.1 | Progress state close on free-space failure | PR #44 / f815415, 96ce0bc | src/99-Main.ps1 | Done | CHANGELOG_STAGE5_PROGRESS_STATE_FAILURE_HANDLING.md |
| Stage 5.2 | Early setup error mutex release | PR #46 / 7624a52, 5e1ac46 | src/99-Main.ps1 | Done | CHANGELOG_STAGE5_EARLY_ERROR_MUTEX_RELEASE.md |
| Stage 6 | GitHub Actions diagnostics | PR #47 / d6541d8, 97f1459 | .github/workflows/*.yml | Done | CHANGELOG_STAGE6_GITHUB_ACTIONS_DIAGNOSTICS.md |
| Stage 7 | CI workflow deduplication | PR #48 / 3396c3a, 8f96a6b | .github/workflows/powershell-syntax.yml | Done | CHANGELOG_STAGE7_CI_WORKFLOW_DEDUPLICATION.md |

## Runtime-поведінка після змін

Після серії Stage 1–5 maintenance-скрипт має контрольованіше завершення у важливих runtime-шляхах:

- фінальне завершення звільняє runtime mutex;
- HealthCheckOnly-завершення звільняє runtime mutex;
- ShowProgressState-завершення звільняє runtime mutex;
- Check-FreeSpace failure закриває progress state як CompletedWithErrors і звільняє runtime mutex;
- ранні помилки після створення mutex, але до progress state initialization, звільняють runtime mutex без спроби закривати progress state.

## CI-поведінка після змін

Після Stage 6–7 GitHub Actions розділено чіткіше:

- bravo-build-validation.yml є основним workflow для source syntax validation, build monolith і перевірки generated output;
- powershell-syntax.yml залишено легким workflow для перевірки root BRAVO_MAINTENANCE.ps1, якщо такий файл є в корені;
- після checkout додано діагностику: поточна директорія, Git HEAD, список файлів, перевірка .git, Build-BRAVO-Monolith.ps1 і src/BRAVO.build.json;
- дублювання build generated monolith прибрано з powershell-syntax.yml.

## Перевірка

Локальні перевірки виконувалися через:

.\Build-BRAVO-Monolith.ps1 -Clean -CreateSha512

Manual GitHub Actions verification:

- Workflow: BRAVO Build Validation
- Event: workflow_dispatch
- Branch: main
- Commit: 6047b04
- Result: Success
- Duration: 22s

## Пов'язані changelog-файли

- CHANGELOG_STAGE1_RUNTIME_STABILITY.md
- CHANGELOG_STAGE3_RUNTIME_FINALLY.md
- CHANGELOG_STAGE4_SHOW_PROGRESS_MUTEX_RELEASE.md
- CHANGELOG_STAGE5_PROGRESS_STATE_FAILURE_HANDLING.md
- CHANGELOG_STAGE5_EARLY_ERROR_MUTEX_RELEASE.md
- CHANGELOG_STAGE6_GITHUB_ACTIONS_DIAGNOSTICS.md
- CHANGELOG_STAGE7_CI_WORKFLOW_DEDUPLICATION.md

## Примітки

Цей документ не замінює деталізовані changelog-файли. Він лише збирає їх у єдину навігаційну точку.

Тимчасові patch-скрипти та backup-директорії не входять у коміти.
