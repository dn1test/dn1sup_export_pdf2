# Changelog (Лог изменений)

Лог изменений **DN1Sup Export PDF 2** (`dn1sup_export_pdf2`).
Формат версий соответствует правилам `MAJOR.MINOR.PATCH`.

## [2.21.9] — 2026-10-17

### DN1Sup Export PDF 2 (v2.21.9)
- **Копия общего апдейтера обновлена до v5.** Объединены ветки: прогресс
  скачивания (status_cb) сохранён, мёртвый локальный канал удалён;
  апдейтер — единая копия для всех расширений DN1Sup, обновление только
  из GitHub Releases.
## [2.21.8] — 2026-10-16

### DN1Sup Export PDF 2 (v2.21.8)
- **Фирменная плитка DN1Sup в шапке GUI** — та же плитка, что в каталоге
  Extension Store (цветной квадрат, знак с «воздухом»); работает в светлой
  и тёмной теме. Источник — `dn1sup_extensions` (`tools/make_icons.rb`).
## [2.21.7] — 2026-10-16

### DN1Sup Export PDF 2 (v2.21.7)
- **Фирменный знак тулбара DN1Sup** — единый стиль каталога Extension
  Store: три знака команд — диалог, быстрый экспорт (молния), рамка пропорций (rose), прозрачный фон, вырезы — настоящая прозрачность
  (SVG-маска; PNG 16/24 — альфа-канал). Источник знака —
  `dn1sup_extensions` → `icons/products/` (`tools/make_icons.rb`).
- Заодно исправлены битые PNG «Быстрого экспорта» (нестандартный IHDR,
  GDI+ показывал «Out of memory» — иконка не отображалась).
- Удалены осиротевшие `ico/project_info.*` (кодом не использовались).

## [2.21.6] — 2026-10-16

- feat(icons): новый дизайн иконки быстрого экспорта — светлый документ PDF
  с красной шапкой и круглым жёлто-оранжевым бейджем-молнией
  (`ico/quick_export.svg`, PNG 16/24px через `tools/make_icons_quick_export.rb`).

## [2.21.5] — 2026-10-16

- feat(ui): переключатель языка в шапке — одна кнопка с глобусом,
  показывает целевой язык (`EN` при русском GUI, `RU` при английском);
  подсказка локализована (`app.languageToEn`/`app.languageToRu`).

## [2.21.4] — 2026-10-16

- fix(updates): недоступный GitHub больше не вводит в заблуждение —
  проверка честно говорит «GitHub не отвечает (...). Проверьте позднее»
  (тост в диалоге / messagebox в меню) вместо молчания или ложного
  «обновлений нет»; различаются лимит API, отсутствие соединения и HTTP-ошибки
  (общий апдейтер: `last_fetch_error`, stage `error` с `code:
  github_unreachable`). Повторное нажатие во время проверки и кнопка
  в рабочей копии больше не вешают спиннер навсегда — возвращается явный
  завершающий stage (`checking` / `dev_copy`).

## [2.21.3] — 2026-10-16

- fix(ui): кнопка обновления в шапке — одна иконка `RotateCw 16` как в остальных
  приложениях (`frontend/.../AppHeader.vue`); соседние иконки `?`/темы/языка
  унифицированы до `16`.

## [2.21.2] — 2026-10-16

- fix(ui): подзаголовки сегментных групп workflow (Ставка/Время/Стоимость,
  Вариант/Ревизия, Старт/Сдача) лишились лишнего `pl-2.5` — все лейблы вкладки
  Project на одной вертикали с обычными полями (`frontend/.../ProjectTab.vue`).
- fix(dev): `update_from_dev.rb` говорил с мостом dn1sup_mcp2 по HTTP POST /eval,
  а мост понимает только TCP newline-JSON — всегда врал «мост не запущен».
  Шаг Hot Reload переписан на `Socket.tcp` + `{"cmd":"eval"}`.

## [2.21.0] — 2026-10-16

- feat(updates): кнопка обновления работает только с GitHub (GitHub
  Releases + registry.json); проверка из локальной папки разработки больше
  не используется (меню, фоновая проверка, кнопка в шапке — через
  `Dn1sup::Updater.check!`). Общий апдейтер v4.
- feat(updates): процесс обновления виден в диалоге — этапы checking →
  found → downloading (проценты) → installing → done через `status_cb`;
  кнопка в шапке показывает спиннер и блокируется на время проверки,
  итог дублируется тостами.

## [2.19.1] — 2026-10-16

- Убран переходный маркер `.sketchup_dev.json` из `dev_source?` (период
  миграции со старых `_dev`-установок завершён); self-update рабочей копии
  определяется только по пути загрузки (признак `!dir.include?('Plugins')`).

## [2.19.0] — 2026-10-15

- Удалён функционал dev/prod (второй id `dn1sup_export_pdf2_dev`): удалены
  `DEV_BUILD`, поле `dev_build` в данных диалога и бейдж DEV в шапке.
  Разработка — рабочая копия под тем же id («Обновить из рабочей копии» /
  Hot Reload). Файлы `.sketchup_dev.json` удалены.
- refactor!: из диалога убраны dev-кнопки обновления из рабочей копии и
  Hot Reload; удалён `update_from_dev.ps1`.
- feat(updates): проверка обновлений из локальной папки разработки и с
  GitHub (кнопка проверки в шапке диалога); общий апдейтер v3 —
  совместимость копий разных версий, учёт даты сборки и времени файлов
  при равной версии.
- feat: `DN1Code::ExportPdf2.unload!` — выгрузка неймспейса: останавливает
  фоновые процессы и снимает наблюдателей (`ObserverService.unregister!`,
  `StatsTracker.unregister!`, `SnapshotWorker.shutdown`,
  `ExportDialog.close`, скрытие Overlay-рамки и тулбара, запись изменённых
  сессий).
- fix: аудит кодовой базы и ребрендинг DN1Sup; `registry.json` — поле
  `author`.

## [2.18.1] — 2026-10-09

- feat: publish for Extension Store - registrar ex.id, registry.json, pack tool + release workflow; docs: PUBLISHING.md + README link
- feat(frontend): add spell check with nspell and shared DN1SUP menu singleton
- Refactor: use Dn1sup.common_menu instead of global variables
- feat: nest Export PDF 2 menu inside shared DN1SUP menu, bump version to 2.16.0
- refactor!: rename package dn1c_export_pdf2 to dn1sup_export_pdf2 (v2.15.0)
- fix(project): prefer server-supplied stadia over empty local list
- feat(history): add SKP backup link tracking and open from history
- feat: add workflow rate and frame overlay flags, widen param zone boxes
- refactor(ui): move font and margin controls into template settings editor header
- fix(template): remove visibility checkbox from parameter cards and bump version to 2.13.1
- feat: remove project status field and rebuild frontend bundle
- fix: persist frame overlay flag before switching scenes to prevent autosave reset
- fix(dn1c_export_pdf2): fix recursive drop callback in useDragSort causing TypeError
- feat(ui): remove font weight/width controls and send fixed defaults
- feat(ui): switch interface font to Roboto Condensed and rebuild assets
- fix(export-pdf2): move zone badge to second card row and bump version to 2.12.5
- feat(templates): add workflow.version_rev parameter and rework template settings editor layout
- feat(project): rework workflow fields with rate/time auto-calculation and plain input styles
- feat: add scenes margin setting, rework header layout, skip master template for empty page type
- fix(ui): refine select styling, scene table widths, and label texts; bump version to 2.9.6
