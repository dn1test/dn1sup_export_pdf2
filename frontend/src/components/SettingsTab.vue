<template>
<!-- Разметка перенесена из App.vue (Фаза 3). Все id сохранены: legacy читает и пишет
     значения контролов напрямую (els map), поэтому биндинги v-model не нужны. -->
<div class="tab-stack">
        <!-- LayOut Parameters Card -->
        <div class="settings-card">
          <div class="card-header">
            <span class="card-header-icon"><i class="modus-icons">layers</i></span>
            <span class="card-header-title">Параметры SketchUp LayOut API</span>
          </div>
          <div class="form-grid">
            <div class="form-group" id="layoutRenderModeGroup">
              <label for="selectLayoutRenderMode">Режим отображения видовых экранов LayOut</label>
              <select id="selectLayoutRenderMode" class="form-control">
                <option value="image" selected>Растровый GPU (Ambient Occlusion, мягкие тени)</option>
                <option value="hybrid">Гибридный (Hybrid, растр + вектор)</option>
              </select>
              <span class="field-hint">Режим GPU рендерит тени Ambient Occlusion напрямую. Гибрид совмещает растровую заливку и векторные линии в одном видовом экране LayOut.</span>
            </div>

            <div class="form-group" id="compressionGroup" style="display: none;">
              <select id="selectCompression" class="form-control">
                <option value="compress" selected>Применять сжатие (Оптимальный размер файла)</option>
                <option value="none">Без сжатия (Максимальное качество, Lossless)</option>
              </select>
            </div>

            <div class="form-group" id="imageFormatGroup">
              <label for="selectImageFormat">Формат изображений</label>
              <select id="selectImageFormat" class="form-control">
                <option value="png" selected>PNG — максимальное сжатие без потерь (24-bit TrueColor)</option>
                <option value="jpg">JPEG — максимальное качество (100%)</option>
              </select>
              <span class="field-hint">PNG использует максимальное сжатие без потерь (TrueColor), JPEG — максимальное качество (100%).</span>
            </div>

            <div class="form-group" id="qualityGroup">
              <label for="selectQuality">Качество разрешения</label>
              <select id="selectQuality" class="form-control">
                <option value="low">low (для экранов 96 dpi)</option>
                <option value="medium" selected>medium (оптимальный 150 dpi)</option>
                <option value="high">high (для печати 300 dpi)</option>
              </select>
              <span class="field-hint">Разрешение вывода: 96 dpi (экраны), 150 dpi (оптимально), 300 dpi (печать).</span>
            </div>

            <div class="form-group" id="scaleMultiplierGroup">
              <label for="selectScaleMultiplier">Толщина линий видового экрана (Множитель толщины линий, pt)</label>
              <select id="selectScaleMultiplier" class="form-control">
                <option value="auto">Авто (подбор под формат листа и разрешение)</option>
                <option value="0.5">0,25 pt (тонкие, 0.5x)</option>
                <option value="1">0,50 pt (стандарт LayOut, 1.0x)</option>
                <option value="1.5">0,75 pt (множитель 1.5x)</option>
                <option value="2.0" selected>1,00 pt (множитель 2.0x)</option>
                <option value="2.5">1,25 pt (множитель 2.5x)</option>
                <option value="3.0">1,50 pt (утолщенные, 3.0x)</option>
              </select>
              <span class="field-hint">Толщина линий 3D-модели в видовом экране LayOut и рендере (0.25–1.50 pt или Авто).</span>
            </div>


            <div class="form-group" id="layoutSaveFileGroup">
              <label class="checkbox-label">
                <input type="checkbox" id="chkSaveLayoutFile" checked>
                <span>Сохранять проект (.layout) рядом с PDF</span>
              </label>
              <span class="field-hint">Файл .layout можно открыть в Trimble LayOut для дальнейшего оформления чертежей.</span>
            </div>
          </div>
        </div>

        <!-- Page and Document Parameters Card -->
        <div class="settings-card">
          <div class="card-header">
            <span class="card-header-icon"><i class="modus-icons">file</i></span>
            <span class="card-header-title">Параметры страницы и документа</span>
          </div>
          <div class="form-grid">
            <div class="form-group">
              <label for="selectPageSize">Формат листа</label>
              <select id="selectPageSize" class="form-control">
                <option value="A3" selected>A3 (297 x 420 мм)</option>
              </select>
            </div>

            <div class="form-group">
              <label for="selectPageLayout">Ориентация страницы</label>
              <select id="selectPageLayout" class="form-control">
                <option value="landscape">Альбомная (Landscape)</option>
                <option value="portrait">Книжная (Portrait)</option>
              </select>
            </div>

            <div class="form-group">
              <label for="inputPageMargin">Отступ по периметру страницы (мм)</label>
              <input type="number" id="inputPageMargin" class="form-control" min="0" max="100" step="1" value="5">
              <span class="field-hint">Поля от края листа (в мм) для всех страниц при экспорте</span>
            </div>

            <div class="form-group" id="fontFamilyGroup">
              <label for="selectFontFamily">Шрифт текста на странице (font_family)</label>
              <select id="selectFontFamily" class="form-control">
                <option value="Sofia Sans Condensed" selected>Sofia Sans Condensed (стандарт)</option>
                <option value="Sofia Sans Extra Condensed">Sofia Sans Extra Condensed (сверхсжатый)</option>
                <option value="Oswald">Oswald</option>
                <option value="Roboto Condensed">Roboto Condensed</option>
                <option value="Ubuntu Condensed">Ubuntu Condensed</option>
              </select>
              <span class="field-hint">Основной шрифт для штампа, таблиц и текстовых блоков страниц документа LayOut / PDF. Вариативные шрифты комплекта содержат все начертания.</span>
            </div>

            <div class="form-group full-width">
              <div class="checkbox-group">
                <label class="checkbox-label">
                  <input type="checkbox" id="chkSaveBackup" checked>
                  <span>Сохранять резервную копию модели (.skp) с номером ревизии</span>
                </label>
                <label class="checkbox-label">
                  <input type="checkbox" id="chkAntialias" checked>
                  <span>Сглаживание линий рендера (Antialiasing)</span>
                </label>
              </div>
            </div>
          </div>
        </div>

        <!-- Section: Обновление плагина (путь к dev-папке резолвится в Ruby, в GUI не показывается) -->
        <div class="settings-card" id="cardPluginUpdate">
          <div class="card-header">
            <div class="card-header-title-wrap">
              <span class="card-header-icon"><i class="modus-icons">autorenew</i></span>
              <span class="card-header-title">Обновление плагина</span>
            </div>
            <span class="badge-dev-version" id="badgeDevVersion" style="font-weight: 600; padding: 2px 7px; border-radius: 4px; background: rgba(0,0,0,0.06); font-size: 11px;">v2.6.0</span>
          </div>
          <p class="field-hint">Проверка новой версии и обновление плагина без ручного копирования файлов. Код обновляется сразу, номер версии применяется после перезапуска SketchUp:</p>
          <div class="form-group" style="margin-bottom: 8px;">
            <div style="display: flex; align-items: center; gap: 6px; min-height: 18px;">
              <span>Текущая версия: <b id="curVersionText">v2.6.0</b></span>
            </div>
            <div id="updateAvailableRow" style="display: none; align-items: center; gap: 6px; margin-top: 4px; color: var(--bs-warning); font-weight: 600;">
              <i class="modus-icons">download</i> Доступна новая версия: <b id="newVersionText"></b>
            </div>
          </div>
          <div style="display: flex; gap: 8px;">
            <button type="button" class="btn btn-xs btn-secondary" id="btnCheckUpdate" title="Сравнить версию в каталоге разработки с установленной"><i class="modus-icons">search</i> Проверить обновление</button>
            <button type="button" class="btn btn-xs btn-primary" id="btnUpdate" title="Скопировать новую версию и перезагрузить плагин" disabled><i class="modus-icons">autorenew</i> Обновить</button>
          </div>
          <div id="devUpdateStatus" class="field-hint" style="font-size: 11px; margin-top: 4px; min-height: 16px;"></div>
        </div>
</div>
</template>
