# Quill

Личное приложение для диктовки на macOS в строке меню: горячая клавиша → речь →
распознавание и постобработка через OpenRouter → вставка в активное окно.

## Сборка

Нужны Xcode 27 (лицензия принята), XcodeGen (`brew install xcodegen`) и вход в Xcode
с Apple ID (Personal Team, подпись Apple Development).

```bash
make test     # тесты логики
make install  # сборка, копия в ~/Applications и запуск
```

## Перенос на другой Mac

```bash
make release   # оптимизированная сборка → build/Quill.zip
```

На другом Mac:

1. Перед первым запуском откройте в Finder «iCloud Drive → Quill» и дождитесь `settings.json` и `profiles/`.
2. Распакуйте `Quill.zip` в `~/Applications` (или `/Applications`).
3. Сборка не нотаризована, поэтому macOS её заблокирует. Один раз выполните
   `xattr -dr com.apple.quarantine ~/Applications/Quill.app`
   или откройте приложение и нажмите «Всё равно открыть» в «Системные настройки → Конфиденциальность и безопасность».
4. Дальше — как «Первый запуск» ниже: ключ OpenRouter, доступ к микрофону и Accessibility, микрофон и горячие клавиши.

## Первый запуск

1. Меню → «Настройки…» → вставить ключ OpenRouter → «Проверить».
2. Разрешить микрофон (спросит при первой записи) и Accessibility (кнопка «Запросить»).
3. Иконка-волна в строке меню; если её не видно (строка переполнена или скрыта «чёлкой»),
   повторно откройте Quill из «Программ» или Spotlight — откроются настройки.
4. ⌥Space — запись (удержание — «держи и говори», короткое нажатие — старт/стоп), Esc — отмена.
   ⌥⇧P — следующий профиль. Клавиши меняются в настройках.

## Профили

Файлы `iCloud Drive/Quill/profiles/*.md` (без iCloud Drive — `~/.config/quill/profiles/`).
Имя файла — id профиля. Профили и `settings.json` в той же папке общие для всех ваших Mac.

**Второй Mac:** перед первым запуском откройте в Finder «iCloud Drive → Quill» и дождитесь,
пока там появятся `settings.json` и `profiles/`. Иначе приложение создаст свои встроенные профили,
и iCloud сделает конфликтные копии (`clean 2.md`, `settings 2.json`) — их можно просто удалить.

```markdown
---
name: Frontend / Claude Code
transcription_model: openai/gpt-4o-transcribe   # необязательно
llm_model: openai/gpt-4.1-mini                  # необязательно
postprocess: true                               # false — вставлять сырой текст
language: ru                                    # необязательно
vocabulary:
  - useState
  - frontend-config
---
Инструкция для постобработки в этом проекте.
```

Словарь применяется только на этапе постобработки: эндпоинт распознавания OpenRouter
подсказки не принимает.

## Данные

- Общие настройки: `iCloud Drive/Quill/settings.json` (модели, лимит аудио, звуки, индикатор)
- История: `~/Library/Application Support/Quill/history.sqlite`
- Аудио: `~/Library/Application Support/Quill/audio/` (ротация по лимиту из настроек, по умолчанию 1 ГБ)
- Ключ: Keychain этой машины, service `dev.saldin.quill` (не синхронизируется: «Настройки… → Показать/Скопировать»)
