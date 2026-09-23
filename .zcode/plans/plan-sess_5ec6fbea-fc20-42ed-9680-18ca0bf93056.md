Переименование подписей во вкладке «Шаблоны» диалога dn1c_export_pdf2:

1. **dn1c_export_pdf2/dialog/html/index.html:254** — заменить текст заголовка левой панели `Шаблоны страниц` → `Название шаблона` (это единственное вхождение этой подписи в UI).

2. **dn1c_export_pdf2/dialog/html/index.html** (блок `#templateSettingsPanel`, ~строка 271) — добавить перед тулбаром правой панели заголовок:
   ```html
   <div class="template-settings-header">
     <div class="sidebar-title-group">
       <span class="sidebar-title-icon">⚙️</span>
       <span class="sidebar-title-text">Параметры шаблона</span>
     </div>
   </div>
   ```
   Используются существующие классы `.sidebar-title-group/-icon/-text`, чтобы типографика совпадала с заголовком левой панели.

3. **dn1c_export_pdf2/dialog/html/app.css** (рядом с `.template-settings-panel`, ~строка 2100) — добавить стиль, зеркалящий `.templates-sidebar-header`:
   ```css
   .template-settings-header {
     display: flex;
     align-items: center;
     padding: 7px 12px;
     background-color: #f8fafc;
     border-bottom: 1px solid #cbd5e1;
     flex-shrink: 0;
   }
   ```

4. **Проверка** — прогнать `test/comprehensive_test.rb`: его регэкспы (строки 5303–5316) якорятся на заголовках карточек вкладки «Настройки» и от этих правок не зависят; правки тестов не требуются. Дополнительно убедиться, что `renderTemplateSettingsList()` заполняет только `#templateSettingsContainer` и новый заголовок не затирается JS (заполнение идёт в контейнер внутри панели — не затирается).

Файлы: index.html, app.css. JS и Ruby-код не меняются.