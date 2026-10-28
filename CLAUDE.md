# CLAUDE.md

## Project

Quill — личное macOS-приложение для диктовки в строке меню (`LSUIElement`, без Dock):
горячая клавиша → запись → распознавание и LLM-постобработка через OpenRouter → вставка в активное окно.
Профили (Markdown с frontmatter) и `settings.json` синхронизируются через iCloud Drive.
Swift 6, macOS 15+, SwiftUI + AppKit. Документация и UI-строки на русском, коммиты на английском.

## Project Map

- `Core/` — SwiftPM-пакет `QuillCore`: вся тестируемая логика, только Foundation/GRDB/Yams.
  - `Pipeline/` — `DictationPipeline` (оркестрация), `Ports.swift` (протоколы `Transcriber`, `PostProcessor`, `Inserter`, `Notifier`, тексты `Notice`), `PromptBuilder`, `RecordGestureMachine`, модели индикатора и меню.
  - `OpenRouter/` — HTTP-клиент с маппингом ошибок (401/402/429/5xx), транскрайбер, постпроцессор.
  - `Storage/` — `HistoryStore` (SQLite + FTS5 через GRDB), `AudioStore` (ротация по размеру).
  - `Profiles/` — парсер frontmatter, `ProfileStore` (слежение за папкой, fallback), встроенные профили.
  - `Sync/` — расположение папки синхронизации, iCloud-плейсхолдеры, `SharedSettingsStore`, `SyncBootstrap` (разовая миграция).
- `App/Sources/` — тонкий слой приложения: `AppController` (сборка зависимостей, хоткеи), `Platform/` (AVFoundation, Keychain, вставка через CGEvent, уведомления), `UI/` (status item, окна настроек и истории, индикатор).
- `docs/superpowers/specs/` — дизайн-спеки (v1, sync); `docs/superpowers/plans/` — планы реализации.
- `README.md` — публичное описание на английском: установка, формат профиля, расположение данных.
- `docs/manual-checklist.md` — ручной чек-лист приёмки.

## Principles

1. **Логика живёт в `Core`, платформа — в `App`.** Core не импортирует AppKit/AVFoundation; платформа подключается через протоколы из `Ports.swift`.
   Why: вся логика покрывается `swift test` без Xcode и без запуска приложения.
2. **Ни одна диктовка не теряется.** Запись в истории создаётся до любого сетевого запроса; статус обновляется на каждом шаге; нераспознанное аудио не попадает под ротацию.
   Why: главный критерий готовности v1 — сбой сети или API не должен съедать продиктованное.
3. **Синхронизируемые файлы пишутся атомарно и читаются терпимо.** Битый `settings.json` или профиль не ломает приложение — используется последнее рабочее состояние и показывается ошибка; iCloud-плейсхолдеры не считаются отсутствующими файлами.
   Why: два Mac пишут в одну папку iCloud, частичные и конфликтные файлы — нормальная ситуация.
4. **Секреты не синхронизируются.** Ключ OpenRouter только в Keychain (`dev.saldin.quill`), не в `settings.json` и не в логах.
   Why: папка синхронизации — обычные файлы в iCloud Drive.
5. **Текст пользователя — данные, а не инструкции.** Расшифровка передаётся LLM внутри `<transcript>`, базовый промпт запрещает выполнять просьбы из неё.
   Why: диктовка часто адресована другому ассистенту («сделай…»), постобработка не должна на неё отвечать.
6. **Новое поведение в Core — через тест.** Сначала тест в `Core/Tests/QuillCoreTests/` (фейки в `Support/`), потом код.
   Why: UI и платформенный слой проверяются только вручную по `docs/manual-checklist.md`.

## Dev Workflow

```bash
make test      # swift test --package-path Core — основная проверка
make install   # xcodegen + Debug-сборка → ~/Applications, перезапуск приложения
make release   # Release-сборка → build/Quill-<версия>.zip
make publish   # тег + GitHub Release; make cask — формула для isaldin/homebrew-tap
```

- `Quill.xcodeproj` и `App/Info.plist` генерируются XcodeGen из `project.yml` и не коммитятся — менять `project.yml`, не проект.
- Подпись Apple Development (Personal Team): при ad-hoc подписи macOS сбрасывает Accessibility после каждой пересборки.
- Новая функциональность: спека в `docs/superpowers/specs/`, план в `docs/superpowers/plans/`, затем мелкие коммиты (один шаг плана — один коммит).
- Поведение, которое нельзя покрыть тестом, добавлять пунктом в `docs/manual-checklist.md`.

## Directory Structure

```
App/Sources/{Platform,UI}/   # приложение: AppKit/SwiftUI/AVFoundation
Core/Sources/QuillCore/{Pipeline,OpenRouter,Storage,Profiles,Sync}/
Core/Tests/QuillCoreTests/  # XCTest, фейки и StubURLProtocol в Support/
docs/superpowers/{specs,plans}/
project.yml  Makefile  README.md
build/ .superpowers/          # не в git
```
