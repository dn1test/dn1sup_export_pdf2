<template>
<!-- Разметка перенесена из исходного dialog/html/index.html (Фаза 0, паритет). -->
  <div class="app-container">
    <!-- Header -->
    <header class="app-header">
      <div class="header-brand">
        <div class="logo-badge" title="Версия плагина: v2.3.0"><i class="modus-icons">file_template</i> export PDF</div>
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
    </nav>

    <!-- Toast Notification: перенесён в Vue-компонент AppToast.vue -->

    <!-- Main Content Area -->
    <main class="app-content">
      <!-- TAB 1: MODULAR PROJECT INFO -->
      <section id="tab-project" class="tab-pane active">
        <!-- Top Row: 2 Columns (1: Паспорт объекта, 2: Карточка заказчика) -->
        <div class="project-columns-row">
          <!-- Column 1: Паспорт объекта (Project) -->
          <div class="settings-card project-col-card">
            <div class="card-header">
              <span class="card-header-icon"><i class="modus-icons">project</i></span>
              <span class="card-header-title">Паспорт объекта (Project)</span>
            </div>
            <div class="form-grid">
              <div class="form-group full-width">
                <label for="inputFurnitureName">Изделие / Название мебели</label>
                <input type="text" id="inputFurnitureName" class="form-control" placeholder="например: Шкаф купе, Тумба, Зеркало">
              </div>

              <div class="form-group">
                <label for="inputRoomName">Комната / Помещение / Место</label>
                <input type="text" id="inputRoomName" class="form-control" placeholder="например: Прихожая, Кухня-гостиная">
              </div>

              <div class="form-group">
                <label for="inputAddress">Адрес установки объекта</label>
                <input type="text" id="inputAddress" class="form-control" placeholder="например: г. Москва, ул. Никитская, д. 12, кв. 45">
              </div>

              <div class="form-group full-width">
                <label for="inputProjectDescription">Описание проекта / задания</label>
                <textarea id="inputProjectDescription" class="form-control" rows="7" placeholder="Краткое описание задания и назначения изделия..."></textarea>
              </div>

            </div>
          </div>

          <!-- Column 2: Карточка заказчика (Customer) -->
          <div class="settings-card project-col-card">
            <div class="card-header">
              <span class="card-header-icon"><i class="modus-icons">account</i></span>
              <span class="card-header-title">Карточка заказчика (Customer)</span>
            </div>
            <div class="form-grid">
              <div class="form-group full-width">
                <label for="inputCustomerId">Идентификатор заказчика (ID)</label>
                <div class="input-action-group">
                  <input type="text" id="inputCustomerId" class="form-control font-mono" placeholder="CUST-260905-142650">
                  <button type="button" class="btn btn-secondary btn-action" id="btnGenerateCustomerId" title="Сгенерировать уникальный идентификатор клиента"><i class="modus-icons">autorenew</i> Создать ID</button>
                </div>
              </div>

              <div class="form-group full-width">
                <label for="inputCustomer">ФИО / Контактное лицо *</label>
                <input type="text" id="inputCustomer" class="form-control" placeholder="например: Мария Смирнова, Алексей">
              </div>

              <div class="form-group full-width" id="companyFieldGroup">
                <label for="inputCompany">Название компании (для коммерческих)</label>
                <input type="text" id="inputCompany" class="form-control" placeholder="ООО &quot;Техно-Дизайн&quot;, ТЦ &quot;Атриум&quot;">
              </div>

              <div class="form-group full-width">
                <label for="inputPhone">Номер телефона</label>
                <input type="text" id="inputPhone" class="form-control" placeholder="+7 (999) 000-00-00">
              </div>

              <div class="form-group full-width">
                <label for="inputEmail">Электронная почта (Email)</label>
                <input type="email" id="inputEmail" class="form-control" placeholder="client@example.com">
              </div>
            </div>
          </div>
        </div>

        <!-- Section 3: Ход работы и жизненный цикл (Workflow) -->
        <div class="settings-card workflow-card">
          <div class="card-header">
            <span class="card-header-icon"><i class="modus-icons">time</i></span>
            <span class="card-header-title">Ход работы и жизненный цикл (Workflow)</span>
          </div>
          <div class="workflow-split-layout">
            <!-- Левая колонка: параметры жизненного цикла -->
            <div class="workflow-left-col">
              <div class="form-grid workflow-grid">
                <div class="form-group span-2">
                  <label for="inputAuthor">Автор / Ответственный конструктор</label>
                  <input type="text" id="inputAuthor" class="form-control" placeholder="например: Иванов И.И.">
                </div>

                <div class="form-group span-2">
                  <label for="inputPrice">Стоимость проекта (руб. / валюта)</label>
                  <input type="text" id="inputPrice" class="form-control" placeholder="например: 125 000">
                </div>

                <div class="form-group span-1">
                  <label for="inputStartDate">Дата начала</label>
                  <input type="date" id="inputStartDate" class="form-control">
                </div>

                <div class="form-group span-1">
                  <label for="inputEndDate">Дата сдачи</label>
                  <input type="date" id="inputEndDate" class="form-control">
                </div>

                <div class="form-group span-2">
                  <label for="inputTotalDuration">Общая длительность проекта</label>
                  <input type="text" id="inputTotalDuration" class="form-control" placeholder="например: 9 дней / 45 часов">
                </div>

                <div class="form-group span-1">
                  <label for="inputVersion">Вариант</label>
                  <input type="number" id="inputVersion" class="form-control" min="1" value="1">
                </div>

                <div class="form-group span-1">
                  <label for="inputRevision">Ревизия</label>
                  <input type="number" id="inputRevision" class="form-control" min="1" value="1">
                </div>

                <div class="form-group span-2">
                  <label for="inputRate">Ставка руб./час</label>
                  <input type="text" id="inputRate" class="form-control">
                </div>

                <div class="form-group full-width">
                  <label for="inputLastEdit">Комментарий к последней правке</label>
                  <input type="text" id="inputLastEdit" class="form-control" placeholder="например: Добавлены замки, правки по люку...">
                </div>
              </div>
            </div>

            <!-- Правая колонка: чекбоксы стадий проекта -->
            <div class="workflow-right-col">
              <div class="workflow-stadia-panel">
                <div class="workflow-stadia-header">
                  <span class="workflow-stadia-icon"><i class="modus-icons">check_mark</i></span>
                  <span class="workflow-stadia-title">Стадии проекта (workflow.stadia):</span>
                </div>
                <div id="stadiaCheckboxesContainer" class="stadia-checkboxes-vertical">
                  <!-- Dynamically populated via JS -->
                </div>
                <div class="stadia-add-row">
                  <input type="text" id="inputNewStadia" class="form-control" placeholder="Название новой стадии...">
                  <button class="btn btn-xs btn-primary" id="btnAddStadia" title="Добавить стадию в конец списка"><i class="modus-icons">add_circle</i> Добавить</button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>
      <!-- TAB 2: PROJECT PAGES / SCENES -->
      <section id="tab-scenes" class="tab-pane">
        <!-- Scenes Panel -->
        <div class="scenes-panel" id="scenesPanel">
          <div class="scenes-toolbar">
            <div class="scenes-quick-actions">
              <button class="btn btn-xs btn-secondary" id="btnSelectAllScenes" title="Выбрать все сцены"><i class="modus-icons">check_mark</i> Все</button>
              <button class="btn btn-xs btn-secondary" id="btnDeselectAllScenes" title="Снять выбор"><i class="modus-icons">content_close</i> Снять</button>
              <button class="btn btn-xs btn-secondary" id="btnRefreshThumbs" title="Перерисовать мини-превью заново: SketchUp по очереди переключится на каждую страницу, снимет свежий эскиз и вернётся на текущую страницу">
                <i class="modus-icons">refresh</i> Обновить эскизы
              </button>
            </div>
            <span class="info-text">Сцены SketchUp и сопоставление с шаблонами:</span>
            <div class="scenes-quick-actions">
              <label class="checkbox-label" title="Фон сцены (небо/земля/туман) включается/выключается сразу на всех страницах и на эскизах; водяные знаки — отдельная галка">
                <input type="checkbox" id="chk_scenes_background">
                <span>Фон</span>
              </label>
              <label class="checkbox-label" title="Водяные знаки из стиля сцены SketchUp включаются/выключаются сразу на всех страницах и на эскизах — независимо от фона">
                <input type="checkbox" id="chk_scenes_watermarks">
                <span>Водяной знак</span>
              </label>
              <label class="checkbox-label" title="Рамка кадра в окне SketchUp: включить/выключить сразу на всех страницах (индивидуально — в меню кадра строки)">
                <input type="checkbox" id="chk_scenes_frame_all">
                <span>Кадр все</span>
              </label>
              <button class="btn btn-xs btn-secondary" id="btnApplyTemplateAll" title="Назначить шаблон из первой строки всем сценам сразу">
                <i class="modus-icons">layers</i> Шаблон всем
              </button>
            </div>
          </div>

          <div class="table-container">
            <table class="scenes-table" id="scenesTable">
              <thead>
                <tr>
                  <th width="34" class="th-check" title="Включить в экспорт">Вкл</th>
                  <th width="44" class="th-order" title="Перетащите строку мышью для изменения порядка следования">№</th>
                  <th width="108" class="th-preview" title="Мини предпросмотр страницы (3:2)">Превью</th>
                  <th>Сцена / Описание</th>
                  <th width="92" class="th-aspect" title="Пропорции кадра, рамка и видовой экран — индивидуально для каждой страницы (меню открывается кликом)">Кадр</th>
                  <th width="74" class="th-scale" title="Размещение картинки на странице, % от листа — индивидуально для каждой страницы">Масштаб</th>
                  <th width="64" class="th-align" title="Выравнивание эскиза на странице — индивидуально для каждой страницы">Выравн.</th>
                  <th width="120" title="Шаблон страницы, назначаемый этой сцене">Шаблон</th>
                </tr>
              </thead>
              <tbody id="scenesTableBody">
                <!-- Dynamically populated via JS -->
              </tbody>
            </table>
          </div>
        </div>
      </section>

      <!-- TAB 3: TEMPLATE SETTINGS -->
      <section id="tab-templates" class="tab-pane">
        <!-- Templates Sidebar (Left) -->
        <aside class="templates-sidebar" id="templatesSidebar">
          <div class="templates-sidebar-header">
            <div class="sidebar-title-group">
              <span class="sidebar-title-icon"><i class="modus-icons">dashboard_customize</i></span>
              <span class="sidebar-title-text">Название шаблона</span>
            </div>
            <div class="sidebar-header-actions">
              <button type="button" class="btn btn-xs btn-primary btn-add-template" id="btnCreateTemplate" title="Создать новый пользовательский шаблон страницы">
                <i class="modus-icons">add_circle</i> Новый
              </button>
            </div>
          </div>
          <div class="templates-list" id="templatesList">
            <!-- Dynamically populated via renderTemplatesList() in app.js -->
          </div>

          <!-- Template Sets: сохранение/загрузка всего списка шаблонов под разные проекты -->
          <div class="templates-sets-section" id="templateSetsSection">
            <div class="templates-sets-header">
              <div class="sidebar-title-group">
                <span class="sidebar-title-icon"><i class="modus-icons">layers</i></span>
                <span class="templates-sets-title">Наборы шаблонов</span>
              </div>
              <button type="button" class="btn btn-xs btn-secondary btn-icon-only" id="btnSaveTemplateSet" title="Сохранить текущий список шаблонов как набор для быстрого переключения между проектами" aria-label="Сохранить набор">
                <i class="modus-icons">save</i>
              </button>
            </div>
            <div class="templates-sets-list" id="templateSetsList">
              <!-- Dynamically populated via renderTemplateSetsList() in app.js -->
            </div>
          </div>
        </aside>

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
                  <label for="selectFontWeight" class="toolbar-label-sub" title="Начертание всего текста PDF: заголовков, таблиц, подвала и штампа">Начертание:</label>
                  <select id="selectFontWeight" class="form-control toolbar-select-sm" title="Начертание всего текста PDF: заголовков, таблиц, подвала и штампа">
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

          <!-- Settings Cards List Container -->
          <div class="template-settings-scroll" id="templateSettingsContainer">
            <!-- Dynamically populated via renderTemplateSettingsList() in app.js -->
          </div>
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

    <!-- New Template Creation Modal -->
    <div id="newTemplateModal" class="modal-overlay hidden">
      <div class="modal-card modal-form-card">
        <div class="modal-header-row">
          <span class="modal-card-icon"><i class="modus-icons">add_circle</i></span>
          <h3>Создание нового шаблона страницы</h3>
        </div>
        <p class="field-hint">Укажите название и описание, выберите основу. Настройки блоков можно будет детально изменить в редакторе:</p>

        <div class="form-group">
          <label for="inputNewTemplateName">Название шаблона *</label>
          <input type="text" id="inputNewTemplateName" class="form-control" placeholder="Например: План расстановки мебели">
        </div>

        <div class="form-group">
          <label for="inputNewTemplateDescription">Описание шаблона</label>
          <input type="text" id="inputNewTemplateDescription" class="form-control" placeholder="Например: План расстановки с размерами (вид сверху)">
        </div>

        <div class="form-group">
          <label for="selectNewTemplateBase">Базовая структура / основа *</label>
          <select id="selectNewTemplateBase" class="form-control">
            <option value="empty" selected>Пустой шаблон — базовый видовой экран</option>
          </select>
        </div>

        <div class="modal-actions">
          <button type="button" class="btn btn-secondary" id="btnCancelNewTemplate"><i class="modus-icons">content_close</i> Отмена</button>
          <button type="button" class="btn btn-primary" id="btnConfirmNewTemplate"><i class="modus-icons">check_mark</i> Создать шаблон</button>
        </div>
      </div>
    </div>

    <!-- Delete Template Confirmation Modal -->
    <div id="deleteTemplateModal" class="modal-overlay hidden">
      <div class="modal-card modal-form-card">
        <div class="modal-header-row modal-header-danger">
          <span class="modal-card-icon"><i class="modus-icons">delete</i></span>
          <h3>Удаление шаблона страницы</h3>
        </div>
        <p id="deleteTemplateMsg" class="modal-msg">
          Вы действительно хотите удалить выбранный шаблон?
        </p>
        <div class="field-hint modal-alert-danger">
          ⚠️ Сцены проекта, использующие этот шаблон, будут автоматически переключены на другой доступный шаблон.
        </div>
        <div class="modal-actions">
          <button type="button" class="btn btn-secondary" id="btnCancelDeleteTemplate"><i class="modus-icons">content_close</i> Отмена</button>
          <button type="button" class="btn btn-danger" id="btnConfirmDeleteTemplate"><i class="modus-icons">delete</i> Удалить шаблон</button>
        </div>
      </div>
    </div>

    <!-- Rename Template Modal -->
    <div id="renameTemplateModal" class="modal-overlay hidden">
      <div class="modal-card modal-form-card">
        <div class="modal-header-row">
          <span class="modal-card-icon"><i class="modus-icons">edit</i></span>
          <h3>Переименование шаблона страницы</h3>
        </div>
        <p class="field-hint">Укажите новое название и описание для этого шаблона страницы:</p>

        <div class="form-group">
          <label for="inputRenameTemplateName">Название шаблона *</label>
          <input type="text" id="inputRenameTemplateName" class="form-control">
        </div>

        <div class="form-group">
          <label for="inputRenameTemplateDescription">Описание шаблона</label>
          <input type="text" id="inputRenameTemplateDescription" class="form-control" placeholder="Отображается в подсказке при наведении на шаблон">
        </div>

        <div class="modal-actions">
          <button type="button" class="btn btn-secondary" id="btnCancelRenameTemplate"><i class="modus-icons">content_close</i> Отмена</button>
          <button type="button" class="btn btn-primary" id="btnConfirmRenameTemplate"><i class="modus-icons">check_mark</i> Сохранить</button>
        </div>
      </div>
    </div>

    <!-- Template Parameter Create/Edit Modal: перенесён в Vue-компонент ParamModal.vue -->

    <!-- Save Template Set Modal -->
    <div id="saveTemplateSetModal" class="modal-overlay hidden">
      <div class="modal-card modal-form-card">
        <div class="modal-header-row">
          <span class="modal-card-icon"><i class="modus-icons">layers</i></span>
          <h3>Сохранение набора шаблонов</h3>
        </div>
        <p class="field-hint">Набор сохраняет текущий список всех шаблонов страниц. Загрузив набор позже, вы мгновенно переключите оформление PDF под другой проект:</p>

        <div class="form-group">
          <label for="inputTemplateSetName">Название набора *</label>
          <input type="text" id="inputTemplateSetName" class="form-control" placeholder="Например: Кухни, Шкафы-купе, Проект Иванов">
        </div>

        <div class="modal-actions">
          <button type="button" class="btn btn-secondary" id="btnCancelSaveTemplateSet"><i class="modus-icons">content_close</i> Отмена</button>
          <button type="button" class="btn btn-primary" id="btnConfirmSaveTemplateSet"><i class="modus-icons">check_mark</i> Сохранить набор</button>
        </div>
      </div>
    </div>

    <!-- Confirm Template Set Action Modal (загрузка / перезапись / удаление) -->
    <div id="confirmTemplateSetModal" class="modal-overlay hidden">
      <div class="modal-card modal-form-card">
        <div class="modal-header-row">
          <span class="modal-card-icon"><i class="modus-icons">layers</i></span>
          <h3 id="confirmTemplateSetTitle">Загрузка набора шаблонов</h3>
        </div>
        <p id="confirmTemplateSetMsg" class="modal-msg">
          Вы действительно хотите загрузить этот набор?
        </p>
        <div id="confirmTemplateSetWarning" class="field-hint modal-alert-danger">
          ⚠️ Текущие шаблоны будут полностью заменены. Сцены, использующие отсутствующие в наборе шаблоны, будут переключены на первый доступный шаблон.
        </div>
        <div class="modal-actions">
          <button type="button" class="btn btn-secondary" id="btnCancelConfirmTemplateSet"><i class="modus-icons">content_close</i> Отмена</button>
          <button type="button" class="btn btn-primary" id="btnConfirmTemplateSet"><i class="modus-icons">check_mark</i> Подтвердить</button>
        </div>
      </div>
    </div>

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
</script>
