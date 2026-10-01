<template>
<!-- Разметка перенесена из исходного dialog/html/index.html (Фаза 0, паритет).
     Тексты — через t() из i18n: смена локали перерисовывает шаблон реактивно. -->
  <div class="app-container">
    <!-- Header -->
    <header class="app-header">
      <div class="header-brand">
        <div class="logo-badge" id="headerVersionBadge" :title="t('app.versionBadgeTitle', { version: '2.6.0' })"><i class="modus-icons">file_template</i> export PDF</div>
        <div class="header-titles">
          <h1 id="headerProjectTitle"></h1>
          <span class="subtitle" id="headerProjectSubtitle"></span>
        </div>
      </div>
      <div class="header-status-group">
        <!-- Переключатель языка интерфейса RU|EN: слева от блока артикула.
             Активная кнопка — реактивно от locale; клик обрабатывает legacy. -->
        <div class="header-lang" id="selectLanguage" :title="t('app.languageTitle')">
          <i class="modus-icons">public</i>
          <div class="header-lang-toggle" role="group" :aria-label="t('app.languageTitle')">
            <button type="button" class="header-lang-btn" :class="{ active: locale === 'ru' }" data-lang="ru">RU</button>
            <button type="button" class="header-lang-btn" :class="{ active: locale === 'en' }" data-lang="en">EN</button>
          </div>
        </div>
        <div class="header-articul" id="headerArticulBlock">
          <span class="header-articul-label"><i class="modus-icons">project</i> {{ t('app.articulLabel') }}</span>
          <div class="header-articul-controls articul-locked">
            <input type="text" id="inputArticul" class="form-control font-mono header-articul-input" placeholder="CF#260905_142650" readonly :title="t('app.articulTitle')">
            <span class="header-trade-badge" id="headerTradeBadge" :title="t('app.tradeTitle')"></span>
          </div>
        </div>
      </div>
    </header>

    <!-- Navigation Tabs -->
    <nav class="nav-tabs">
      <button class="tab-btn active" data-tab="tab-project">
        <span class="tab-icon"><i class="modus-icons">project</i></span> {{ t('tabs.project') }}
      </button>
      <button class="tab-btn" data-tab="tab-scenes">
        <span class="tab-icon"><i class="modus-icons">layers</i></span> {{ t('tabs.scenes') }}
        <span class="badge" id="sceneCountBadge">0</span>
      </button>
      <button class="tab-btn" data-tab="tab-templates">
        <span class="tab-icon"><i class="modus-icons">dashboard_customize</i></span> {{ t('tabs.templates') }}
      </button>
      <button class="tab-btn" data-tab="tab-directories">
        <span class="tab-icon"><i class="modus-icons">folder</i></span> {{ t('tabs.directories') }}
      </button>
      <button class="tab-btn" data-tab="tab-history">
        <span class="tab-icon"><i class="modus-icons">time</i></span> {{ t('tabs.history') }}
      </button>
      <button class="tab-btn" data-tab="tab-stats">
        <span class="tab-icon"><i class="modus-icons">insert_chart</i></span> {{ t('tabs.stats') }}
      </button>
      <button class="tab-btn tab-btn-settings" data-tab="tab-settings">
        <span class="tab-icon"><i class="modus-icons">settings</i></span> {{ t('tabs.settings') }}
      </button>
      <button class="tab-btn" data-tab="tab-send">
        <span class="tab-icon"><i class="modus-icons">file_upload</i></span> {{ t('tabs.send') }}
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
              <span class="sidebar-title-text">{{ t('tpl.panelTitle') }}</span>
            </div>
            <div class="template-settings-actions">
              <button class="btn btn-xs btn-secondary" id="btnResetLayout" :title="t('tpl.resetTitle')">
                <i class="modus-icons">action_undo</i> {{ t('tpl.resetBtn') }}
              </button>
              <button class="btn btn-xs btn-danger-outline" id="btnDeleteCurrentTemplate" :title="t('tpl.deleteTitle')" style="display: none;">
                <i class="modus-icons">delete</i> {{ t('tpl.deleteBtn') }}
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
                <button type="button" class="btn btn-xs btn-secondary" id="btnRenameCurrentTemplate" :title="t('tpl.renameTitle')" :aria-label="t('tpl.renameAria')" style="display: none;">
                  <i class="modus-icons">edit</i>
                </button>
                <span class="layout-page-info" id="layoutPageInfoBadge"></span>
              </div>

              <span class="layout-tpl-usage" id="layoutTplUsageBadge"></span>

              <div class="toolbar-group">
                <div class="toolbar-font-control">
                  <label for="selectLayoutFontFamily" class="toolbar-label-sub" :title="t('tpl.fontTitle')">{{ t('tpl.fontLabel') }}</label>
                  <select id="selectLayoutFontFamily" class="form-control toolbar-select-sm" :title="t('tpl.fontDocTitle')">
                    <option value="Sofia Sans Condensed">Sofia Sans Condensed</option>
                    <option value="Sofia Sans Extra Condensed">Sofia Sans Extra Condensed</option>
                    <option value="Oswald">Oswald</option>
                    <option value="Roboto Condensed">Roboto Condensed</option>
                    <option value="Ubuntu Condensed">Ubuntu Condensed</option>
                  </select>
                </div>
                <div class="toolbar-font-control">
                  <label for="selectFontWeight" class="toolbar-label-sub" :title="t('tpl.weightTitle')">{{ t('tpl.weightLabel') }}</label>
                  <select id="selectFontWeight" class="form-control toolbar-select-sm" :title="t('tpl.weightTitle')">
                    <option value="normal" selected>{{ t('tpl.weightNormal') }}</option>
                    <option value="bold">{{ t('tpl.weightBold') }}</option>
                  </select>
                </div>
                <div class="toolbar-font-control">
                  <label for="selectFontWidth" class="toolbar-label-sub" :title="t('tpl.widthTitle')">{{ t('tpl.widthLabel') }}</label>
                  <select id="selectFontWidth" class="form-control toolbar-select-sm" :title="t('tpl.widthTitle')">
                    <option value="condensed" selected>{{ t('tpl.widthCondensed') }}</option>
                    <option value="extra_condensed">{{ t('tpl.widthExtra') }}</option>
                  </select>
                </div>
                <div class="toolbar-margin-control">
                  <label for="inputLayoutMargin" class="toolbar-label-sub" :title="t('tpl.marginTitle')">{{ t('tpl.marginLabel') }}</label>
                  <input type="number" id="inputLayoutMargin" class="form-control" min="0" max="100" step="1" value="5" :title="t('tpl.marginInputTitle')">
                  <span class="unit-text">{{ t('tpl.mmUnit') }}</span>
                </div>
              </div>
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
        <h3 id="progressTitle">{{ t('progress.title') }}</h3>
        <p id="progressMessage">{{ t('progress.initial') }}</p>
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
            <h3 class="modal-title">{{ t('rev.title') }}</h3>
            <p class="modal-subtitle">{{ t('rev.subtitle') }}</p>
          </div>
        </div>

        <div class="revision-modal-body">
          <div class="revision-meta-grid">
            <div class="rev-meta-item">
              <span class="rev-meta-label">{{ t('rev.exactDateTime') }}</span>
              <span class="rev-meta-value font-mono" id="revPromptDateTime">2026-09-07 00:30</span>
            </div>
            <div class="rev-meta-item">
              <span class="rev-meta-label">{{ t('rev.revisionNumber') }}</span>
              <span class="rev-meta-value font-mono"><span id="revPromptCurrentRev">r002</span> &rarr; <span class="rev-next-badge" id="revPromptNextRev">r003</span></span>
            </div>
          </div>

          <div class="rev-input-wrapper">
            <label for="inputRevisionNote" class="rev-input-label">{{ t('rev.noteLabel') }}</label>
            <textarea id="inputRevisionNote" class="form-control rev-textarea" rows="3" :placeholder="t('rev.notePh')"></textarea>
            <span class="rev-input-hint">{{ t('rev.hint') }}</span>
          </div>
        </div>

        <div class="modal-actions revision-modal-actions">
          <button type="button" class="btn btn-secondary" id="btnCancelExportModal"><i class="modus-icons">content_close</i> {{ t('common.cancel') }}</button>
          <div class="rev-modal-action-group">
            <button type="button" class="btn btn-secondary" id="btnSkipRevisionExport" :title="t('rev.skipTitle')"><i class="modus-icons">launch</i> {{ t('rev.skip') }}</button>
            <button type="button" class="btn btn-success" id="btnConfirmRevisionExport" :title="t('rev.confirmTitle')"><i class="modus-icons">save</i> {{ t('rev.confirm') }}</button>
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
            <h3 class="modal-title">{{ t('articulType.title') }}</h3>
            <p class="modal-subtitle">{{ t('articulType.subtitle') }}</p>
          </div>
        </div>

        <div class="revision-modal-body">
          <div class="rev-input-hint">{{ t('articulType.hint') }}</div>
        </div>

        <div class="modal-actions revision-modal-actions">
          <button type="button" class="btn btn-secondary" id="btnArticulTypeLater"><i class="modus-icons">time</i> {{ t('articulType.later') }}</button>
          <div class="rev-modal-action-group">
            <button type="button" class="btn btn-primary" id="btnArticulTypeCommercial" :title="t('articulType.commercialTitle')"><i class="modus-icons">user_group</i> {{ t('articulType.commercial') }}</button>
            <button type="button" class="btn btn-success" id="btnArticulTypeHousehold" :title="t('articulType.householdTitle')"><i class="modus-icons">account</i> {{ t('articulType.household') }}</button>
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
            <h3 class="modal-title">{{ t('articulPrompt.title') }}</h3>
            <p class="modal-subtitle">{{ t('articulPrompt.subtitle') }}</p>
          </div>
        </div>

        <div class="revision-modal-body">
          <div class="rev-input-wrapper">
            <label for="inputArticulPrompt" class="rev-input-label">{{ t('articulPrompt.label') }}</label>
            <input type="text" id="inputArticulPrompt" class="form-control font-mono" :placeholder="t('articulPrompt.ph')" autocomplete="off" />
            <span class="rev-input-hint">{{ t('articulPrompt.hint') }}</span>
          </div>
        </div>

        <div class="modal-actions revision-modal-actions">
          <button type="button" class="btn btn-secondary" id="btnCancelArticulPrompt"><i class="modus-icons">content_close</i> {{ t('common.cancel') }}</button>
          <button type="button" class="btn btn-success" id="btnConfirmArticulSave" :title="t('articulPrompt.confirmTitle')"><i class="modus-icons">check_mark</i> {{ t('articulPrompt.confirm') }}</button>
        </div>
      </div>
    </div>

    <!-- Export Success Modal -->
    <div id="successModal" class="modal-overlay hidden">
      <div class="modal-card success-modal-card">
        <div class="success-modal-icon"><i class="modus-icons">check_circle</i></div>
        <h3 class="success-modal-title">{{ t('success.title') }}</h3>
        <div class="success-modal-path-box">
          <span class="success-path-label">{{ t('success.pathLabel') }}</span>
          <p class="modal-file-path font-mono" id="successPdfPath" :title="t('success.pathTitle')"></p>
        </div>
        <div class="modal-actions success-modal-actions">
          <button class="btn btn-secondary" id="btnOpenPdfFolder"><i class="modus-icons">folder</i> {{ t('success.openFolder') }}</button>
          <button class="btn btn-primary" id="btnCloseSuccessModal"><i class="modus-icons">check_mark</i> {{ t('success.done') }}</button>
        </div>
      </div>
    </div>



    <!-- Template Parameter Create/Edit Modal: перенесён в Vue-компонент ParamModal.vue -->



    <!-- Footer Action Bar -->
    <footer class="app-footer">
      <div class="footer-left">
        <button class="btn btn-secondary" id="btnSaveYaml" :title="t('footer.saveTitle')"><i class="modus-icons">save</i> {{ t('footer.saveBtn') }}</button>
        <button class="btn btn-secondary" id="btnImportYaml" :title="t('footer.importTitle')"><i class="modus-icons">file_download</i> {{ t('footer.importYaml') }}</button>
        <button class="btn btn-secondary" id="btnExportYaml" :title="t('footer.exportTitle')"><i class="modus-icons">file_upload</i> {{ t('footer.exportYaml') }}</button>
        <div class="autosave-status" id="autosaveStatus" :title="t('footer.autosaveTitle')">
          <span class="autosave-dot" id="autosaveDot"></span>
          <span class="autosave-text" id="autosaveText"></span>
        </div>
      </div>
      <div class="footer-right">
        <label class="footer-checkbox-label" :title="t('footer.autoOpenTitle')">
          <input type="checkbox" id="chkAutoOpen" checked>
          <span>{{ t('footer.autoOpen') }}</span>
        </label>
        <button class="btn btn-success" id="btnStartExport"><i class="modus-icons">launch</i> {{ t('footer.exportBtn') }}</button>
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
import { t, locale } from './i18n/index.js'
</script>
