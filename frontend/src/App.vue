<template>
<!-- Разметка перенесена из исходного dialog/html/index.html (Фаза 0, паритет). -->
  <div class="app-container">
    <!-- Header -->
    <header class="app-header">
      <div class="header-brand">
        <div class="logo-badge" title="Версия плагина: v2.5.0"><i class="modus-icons">file_template</i> export PDF</div>
        <div class="header-titles">
          <h1 id="headerProjectTitle">Новый проект</h1>
          <span class="subtitle" id="headerProjectSubtitle">Заказчик — Адрес объекта</span>
        </div>
      </div>
      <div class="header-status-group">
        <div class="header-articul" id="headerArticulBlock">
          <span class="header-articul-label"><i class="modus-icons">project</i> АРТИКУЛ</span>
          <div class="header-articul-controls articul-locked">
            <input type="text" id="inputArticul" class="form-control font-mono header-articul-input" placeholder="CF#260905_142650" readonly title="Артикул создаётся один раз при выборе типа проекта и не изменяется">
            <span class="header-trade-badge trade-unset" id="headerTradeBadge" title="Тип проекта — выбирается при создании артикула и больше не меняется">Тип не выбран</span>
          </div>
        </div>
      </div>
    </header>

    <!-- Navigation Tabs -->
    <nav class="nav-tabs">
      <button class="tab-btn active" data-tab="tab-project">
        <span class="tab-icon"><i class="modus-icons">project</i></span> Проект
      </button>
      <button class="tab-btn" data-tab="tab-scenes">
        <span class="tab-icon"><i class="modus-icons">layers</i></span> Страницы
        <span class="badge" id="sceneCountBadge">0</span>
      </button>
      <button class="tab-btn" data-tab="tab-templates">
        <span class="tab-icon"><i class="modus-icons">dashboard_customize</i></span> Шаблоны
      </button>
      <button class="tab-btn" data-tab="tab-directories">
        <span class="tab-icon"><i class="modus-icons">folder</i></span> Папки
      </button>
      <button class="tab-btn" data-tab="tab-history">
        <span class="tab-icon"><i class="modus-icons">time</i></span> История
      </button>
      <button class="tab-btn tab-btn-settings" data-tab="tab-settings">
        <span class="tab-icon"><i class="modus-icons">settings</i></span> Настройки
      </button>
      <button class="tab-btn" data-tab="tab-send">
        <span class="tab-icon"><i class="modus-icons">file_upload</i></span> Отправка
      </button>
      <button class="tab-btn" data-tab="tab-stats">
        <span class="tab-icon"><i class="modus-icons">insert_chart</i></span> Статистика
      </button>
    </nav>

    <!-- Toast Notification: перенесён в Vue-компонент AppToast.vue -->

    <!-- Main Content Area -->
    <main class="app-content">
      <!-- TAB 1: MODULAR PROJECT INFO -->
      <!-- TAB 1: MODULAR PROJECT INFO — рендерится Vue-компонентом -->
      <section id="tab-project" class="tab-pane active">
        <ProjectTab />
      </section>
      <!-- TAB 2: PROJECT PAGES / SCENES -->
      <!-- TAB 2: PROJECT PAGES / SCENES — рендерится Vue-компонентом -->
      <section id="tab-scenes" class="tab-pane">
        <ScenesTab />
      </section>

      <!-- TAB 3: TEMPLATE SETTINGS -->
      <section id="tab-templates" class="tab-pane">
        <!-- Templates Sidebar (Left) — Vue-компонент -->
        <TemplatesSidebar />
        <!-- Модалки шаблонов и наборов — Vue-компонент -->
        <TemplateModals />

        <!-- Template & List Settings Panel (Right) -->
        <div class="template-settings-panel" id="templateSettingsPanel">
          <!-- Panel Header -->
          <div class="template-settings-header">
            <div class="sidebar-title-group">
              <span class="sidebar-title-icon"><i class="modus-icons">tune</i></span>
              <span class="sidebar-title-text">Параметры шаблона</span>
            </div>
            <div class="template-settings-actions">
              <button class="btn btn-xs btn-secondary" id="btnResetLayout" title="Сбросить настройки текущего шаблона к стандартным">
                <i class="modus-icons">action_undo</i> Сбросить
              </button>
              <button class="btn btn-xs btn-danger-outline" id="btnDeleteCurrentTemplate" title="Удалить этот пользовательский шаблон" style="display: none;">
                <i class="modus-icons">delete</i> Удалить шаблон
              </button>
            </div>
          </div>
          <!-- Toolbar -->
          <div class="template-settings-toolbar">
            <div class="toolbar-row toolbar-main-row">
              <div class="toolbar-group template-header-info">
                <span class="current-template-title" id="currentTemplateTitle">Титульный лист (Cover)</span>
                <select id="selectLayoutTemplate" class="form-control toolbar-select" style="display: none;">
                  <!-- Опции заполняются динамически (syncTemplateDropdowns) -->
                </select>
                <button type="button" class="btn btn-xs btn-secondary" id="btnRenameCurrentTemplate" title="Переименовать этот шаблон" style="display: none;">
                  <i class="modus-icons">edit</i> Переименовать
                </button>
                <span class="layout-page-info" id="layoutPageInfoBadge">A3 Альбомная</span>
              </div>

              <div class="toolbar-group">
                <div class="toolbar-font-control">
                  <label for="selectLayoutFontFamily" class="toolbar-label-sub" title="Шрифт текста страниц">Шрифт:</label>
                  <select id="selectLayoutFontFamily" class="form-control toolbar-select-sm" title="Шрифт текста страниц документа">
                    <option value="Sofia Sans Condensed">Sofia Sans Condensed</option>
                    <option value="Sofia Sans Extra Condensed">Sofia Sans Extra Condensed</option>
                    <option value="Oswald">Oswald</option>
                    <option value="Roboto Condensed">Roboto Condensed</option>
                    <option value="Ubuntu Condensed">Ubuntu Condensed</option>
                  </select>
                </div>
                <div class="toolbar-font-control">
                  <label for="selectFontWeight" class="toolbar-label-sub" title="Начертание всего текста PDF: заголовков, таблиц, подвала">Начертание:</label>
                  <select id="selectFontWeight" class="form-control toolbar-select-sm" title="Начертание всего текста PDF: заголовков, таблиц, подвала">
                    <option value="normal" selected>Обычное</option>
                    <option value="bold">Жирное</option>
                  </select>
                </div>
                <div class="toolbar-font-control">
                  <label for="selectFontWidth" class="toolbar-label-sub" title="Ширина шрифта: повышает сжатие Sofia Sans Condensed до Extra Condensed. Для Oswald, Roboto Condensed и Ubuntu Condensed ширина фиксированная">Ширина:</label>
                  <select id="selectFontWidth" class="form-control toolbar-select-sm" title="Ширина шрифта: повышает сжатие Sofia Sans Condensed до Extra Condensed. Для Oswald, Roboto Condensed и Ubuntu Condensed ширина фиксированная">
                    <option value="condensed" selected>Узкая</option>
                    <option value="extra_condensed">Сверхузкая</option>
                  </select>
                </div>
                <div class="toolbar-margin-control">
                  <label for="inputLayoutMargin" class="toolbar-label-sub" title="Отступ по периметру страницы">Поля листа:</label>
                  <input type="number" id="inputLayoutMargin" class="form-control" min="0" max="100" step="1" value="5" title="Отступ по периметру страницы в мм">
                  <span class="unit-text">мм</span>
                </div>
              </div>
            </div>

            <div class="toolbar-row toolbar-usage-row">
              <span class="layout-tpl-usage" id="layoutTplUsageBadge" title="Сцены SketchUp, использующие этот шаблон"></span>
            </div>
          </div>

          <!-- Settings Cards List — рендерится Vue-компонентом -->
          <TemplateSettingsEditor />
        </div>
      </section>

      <!-- TAB: DIRECTORIES, SPECIFICATIONS & PREVIEWS — рендерится Vue-компонентом -->
      <section id="tab-directories" class="tab-pane">
        <DirectoriesTab />
      </section>

      <!-- TAB 5: HISTORY -->
      <!-- TAB 5: HISTORY — рендерится Vue-компонентом -->
      <section id="tab-history" class="tab-pane">
        <HistoryTab />
      </section>

      <!-- TAB 6: SETTINGS -->
      <!-- TAB: SETTINGS — рендерится Vue-компонентом -->
      <section id="tab-settings" class="tab-pane">
        <SettingsTab />
      </section>

      <!-- TAB 7: SEND -->
      <!-- TAB 7: SEND — рендерится Vue-компонентом -->
      <section id="tab-send" class="tab-pane">
        <SendTab />
      </section>

      <!-- TAB 8: WORK-TIME STATISTICS — рендерится Vue-компонентом -->
      <section id="tab-stats" class="tab-pane">
        <StatsTab />
      </section>
    </main>

    <!-- Progress Overlay -->
    <div id="progressOverlay" class="progress-overlay hidden">
      <div class="progress-card">
        <div class="progress-spinner"></div>
        <h3 id="progressTitle">Генерация PDF документа...</h3>
        <p id="progressMessage">Подготовка сцен к рендерингу</p>
        <div class="progress-bar-track">
          <div class="progress-bar-fill" id="progressBarFill" style="width: 0%;"></div>
        </div>
        <span class="progress-percent" id="progressPercent">0%</span>
      </div>
    </div>

    <!-- Revision Prompt Modal before PDF Export -->
    <div id="revisionPromptModal" class="modal-overlay hidden">
      <div class="modal-card revision-modal-card">
        <div class="modal-header-with-icon">
          <div class="modal-badge-icon"><i class="modus-icons">edit</i></div>
          <div class="modal-header-text">
            <h3 class="modal-title">Внесение правок в проект</h3>
            <p class="modal-subtitle">Зафиксируйте выполненные изменения перед созданием PDF</p>
          </div>
        </div>
        
        <div class="revision-modal-body">
          <div class="revision-meta-grid">
            <div class="rev-meta-item">
              <span class="rev-meta-label">Точная дата и время</span>
              <span class="rev-meta-value font-mono" id="revPromptDateTime">2026-09-07 00:30</span>
            </div>
            <div class="rev-meta-item">
              <span class="rev-meta-label">Номер ревизии</span>
              <span class="rev-meta-value font-mono"><span id="revPromptCurrentRev">r002</span> &rarr; <span class="rev-next-badge" id="revPromptNextRev">r003</span></span>
            </div>
          </div>

          <div class="rev-input-wrapper">
            <label for="inputRevisionNote" class="rev-input-label">Какие правки были сделаны:</label>
            <textarea id="inputRevisionNote" class="form-control rev-textarea" rows="3" placeholder="Опишите внесенные правки (например: Скорректированы размеры шкафа, изменен цвет фасадов)..."></textarea>
            <span class="rev-input-hint">Нажмите «Записать и создать PDF» для сохранения в историю проекта с точной датой и временем, или «Без записи правок», если ревизия не изменялась.</span>
          </div>
        </div>

        <div class="modal-actions revision-modal-actions">
          <button type="button" class="btn btn-secondary" id="btnCancelExportModal"><i class="modus-icons">content_close</i> Отмена</button>
          <div class="rev-modal-action-group">
            <button type="button" class="btn btn-secondary" id="btnSkipRevisionExport" title="Создать PDF без внесения новой записи в историю"><i class="modus-icons">launch</i> Без записи правок</button>
            <button type="button" class="btn btn-success" id="btnConfirmRevisionExport" title="Записать правки в историю с точным временем и датой и создать PDF"><i class="modus-icons">save</i> Записать и создать PDF</button>
          </div>
        </div>
      </div>
    </div>

    <!-- Articul Type Modal: предложение создать артикул при открытии панели -->
    <div id="articulTypeModal" class="modal-overlay hidden">
      <div class="modal-card revision-modal-card">
        <div class="modal-header-with-icon">
          <div class="modal-badge-icon"><i class="modus-icons">project</i></div>
          <div class="modal-header-text">
            <h3 class="modal-title">Создать артикул проекта</h3>
            <p class="modal-subtitle">Выберите тип проекта — артикул будет сгенерирован автоматически</p>
          </div>
        </div>

        <div class="revision-modal-body">
          <div class="rev-input-hint">Рядом с рабочим файлом .skp будет создана папка по имени артикула. В ней хранятся все данные проекта: project.yaml, PDF, резервные копии SKP и снимки сцен.</div>
        </div>

        <div class="modal-actions revision-modal-actions">
          <button type="button" class="btn btn-secondary" id="btnArticulTypeLater"><i class="modus-icons">time</i> Позже</button>
          <div class="rev-modal-action-group">
            <button type="button" class="btn btn-primary" id="btnArticulTypeCommercial" title="Артикул коммерческого проекта: CF#ГГММДД_ЧЧММСС"><i class="modus-icons">user_group</i> Коммерческий проект</button>
            <button type="button" class="btn btn-success" id="btnArticulTypeHousehold" title="Артикул бытового проекта: HF#ГГММДД_ЧЧММСС"><i class="modus-icons">account</i> Бытовой проект</button>
          </div>
        </div>
      </div>
    </div>

    <!-- Articul Prompt Modal: сохранение/экспорт невозможны без артикула -->
    <div id="articulPromptModal" class="modal-overlay hidden">
      <div class="modal-card revision-modal-card">
        <div class="modal-header-with-icon">
          <div class="modal-badge-icon"><i class="modus-icons">project</i></div>
          <div class="modal-header-text">
            <h3 class="modal-title">Не указан артикул проекта</h3>
            <p class="modal-subtitle">Без артикула данные проекта не сохраняются — нельзя создать папку проекта</p>
          </div>
        </div>

        <div class="revision-modal-body">
          <div class="rev-input-wrapper">
            <label for="inputArticulPrompt" class="rev-input-label">Артикул проекта:</label>
            <input type="text" id="inputArticulPrompt" class="form-control font-mono" placeholder="Например: CF#260921_153000" autocomplete="off" />
            <span class="rev-input-hint">Предложен сгенерированный артикул — можно вписать свой. «Создать и сохранить» создаст папку проекта и запишет данные.</span>
          </div>
        </div>

        <div class="modal-actions revision-modal-actions">
          <button type="button" class="btn btn-secondary" id="btnCancelArticulPrompt"><i class="modus-icons">content_close</i> Отмена</button>
          <button type="button" class="btn btn-success" id="btnConfirmArticulSave" title="Создать артикул и сохранить данные проекта в папку артикула"><i class="modus-icons">check_mark</i> Создать и сохранить</button>
        </div>
      </div>
    </div>

    <!-- Export Success Modal -->
    <div id="successModal" class="modal-overlay hidden">
      <div class="modal-card success-modal-card">
        <div class="success-modal-icon"><i class="modus-icons">check_circle</i></div>
        <h3 class="success-modal-title">PDF успешно создан!</h3>
        <div class="success-modal-path-box">
          <span class="success-path-label">Файл документа:</span>
          <p class="modal-file-path font-mono" id="successPdfPath" title="Путь к созданному PDF"></p>
        </div>
        <div class="modal-actions success-modal-actions">
          <button class="btn btn-secondary" id="btnOpenPdfFolder"><i class="modus-icons">folder</i> Открыть папку</button>
          <button class="btn btn-primary" id="btnCloseSuccessModal"><i class="modus-icons">check_mark</i> Готово</button>
        </div>
      </div>
    </div>




    <!-- Template Parameter Create/Edit Modal: перенесён в Vue-компонент ParamModal.vue -->



    <!-- Footer Action Bar -->
    <footer class="app-footer">
      <div class="footer-left">
        <button class="btn btn-secondary" id="btnSaveYaml" title="Принудительно сохранить: YAML проекта рядом с .skp + настройки PDF и шаблоны в YAML расширения (также сохраняется при экспорте PDF и закрытии SketchUp)"><i class="modus-icons">save</i> Принудительно сохранить</button>
        <button class="btn btn-secondary" id="btnImportYaml" title="Импортировать данные проекта из YAML в память (запись на диск — кнопкой принудительного сохранения)"><i class="modus-icons">file_download</i> Импорт YAML</button>
        <button class="btn btn-secondary" id="btnExportYaml" title="Экспортировать настройки в YAML"><i class="modus-icons">file_upload</i> Экспорт YAML</button>
        <div class="autosave-status" id="autosaveStatus" title="Автосохранение данных в YAML">
          <span class="autosave-dot" id="autosaveDot"></span>
          <span class="autosave-text" id="autosaveText">YAML сохранен</span>
        </div>
      </div>
      <div class="footer-right">
        <label class="footer-checkbox-label" title="Автоматически открыть созданный PDF в программе по умолчанию">
          <input type="checkbox" id="chkAutoOpen" checked>
          <span>Открыть после экспорта</span>
        </label>
        <button class="btn btn-success" id="btnStartExport"><i class="modus-icons">launch</i> Экспорт в PDF</button>
      </div>
    </footer>

    <!-- Vue: общие компоненты (тосты, модалки) -->
    <AppToast />
    <ParamModal />
  </div>
</template>

<script setup>
import AppToast from './components/AppToast.vue'
import ParamModal from './components/ParamModal.vue'
import DirectoriesTab from './components/DirectoriesTab.vue'
import SettingsTab from './components/SettingsTab.vue'
import HistoryTab from './components/HistoryTab.vue'
import SendTab from './components/SendTab.vue'
import StatsTab from './components/StatsTab.vue'
import ProjectTab from './components/ProjectTab.vue'
import ScenesTab from './components/ScenesTab.vue'
import TemplatesSidebar from './components/TemplatesSidebar.vue'
import TemplateModals from './components/TemplateModals.vue'
import TemplateSettingsEditor from './components/TemplateSettingsEditor.vue'
</script>
