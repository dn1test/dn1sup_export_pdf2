# Публикация расширения на GitHub

> Полная общая инструкция — мастер `U:\dn1code\sketchup_ext\PUBLISHING.md`
> (единственная полная копия: как Store ищет репозитории, обязательные
> требования, registry.json, версии и changelog, релизы). Ниже — локальный
> чек-лист этого репозитория.

## Чек-лист этого репозитория

| Требование | Статус |
|---|---|
| Имя `dn1sup_*` в аккаунте `dn1test` | ⏳ создайте репозиторий на GitHub и назначьте его origin (старые `fg`/`gt` смотрят на `dn1codegen`) |
| Не archived | ✅ (применимо после публикации) |
| `registry.json` в корне `main` | ✅ создан (version 2.18.1, синхронизируется `tools/pack.rb`) |
| Стабильные релизы с `.rbz` | ⏳ `tools/pack.rb` и workflow добавлены — нужен push и тег |
| Теги `vMAJOR.MINOR.PATCH` | ⏳ проставьте тег `v2.18.1` при публикации |
| Регистратор `<id>.rb` + `ext.id` | ✅ `ex.id = 'dn1sup_export_pdf2'` задан |

Осталось опубликовать:

1. Создайте на GitHub `dn1test/dn1sup_export_pdf2` и добавьте remote:
   `git remote add origin git@github.com:dn1test/dn1sup_export_pdf2.git`.
2. Закоммитьте изменения и запушьте ветку `main`.
3. Первая публикация: тег `v2.18.1` → workflow соберёт
   `dist/dn1sup_export_pdf2-2.18.1.rbz` и приложит к релизу.
4. По желанию: `shared/dn1sup_updater.rb` для «Проверить обновления».
