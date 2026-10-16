// App-стор: активная вкладка, прогресс экспорта, глобальные модалки
// (ревизия/артикул/успех), экспортный флоу, обновление плагина с GitHub.

import { defineStore } from 'pinia'
import { callRuby } from '../bridge/sketchup.js'
import { collectFormData } from '../bridge/payload.js'
import { flushAutoSave, notifyChange } from './autosave.js'
import { showToast } from './toast.js'
import { setLocale, t } from '../i18n/index.js'
import { nowStamp } from '../lib/dates.js'
import { useProjectStore, generateArticulLocal } from './project.js'
import { useScenesStore } from './scenes.js'
import { useTemplatesStore } from './templates.js'
import { useDirectoriesStore } from './directories.js'
import { useSettingsStore } from './settings.js'
import { useStatsStore } from './stats.js'

const STATS_AUTO_REFRESH_MS = 60000
let statsAutoTimer = null

export const TAB_IDS = [
  'tab-project',
  'tab-scenes',
  'tab-templates',
  'tab-directories',
  'tab-history',
  'tab-stats',
  'tab-settings',
  'tab-send',
]

export const useAppStore = defineStore('app', {
  state: () => ({
    activeTab: 'tab-project',
    pluginVersion: '',
    progress: { visible: false, percent: 0, message: '' },
    // Предложение создать артикул при открытии панели
    articulTypeModal: { visible: false },
    // Обязательный артикул перед сохранением/экспортом
    articulPrompt: { visible: false, value: '', action: null },
    // Промпт ревизии перед экспортом
    revisionModal: { visible: false, dateTime: '', currRev: '', nextRev: '', note: '' },
    // Успешный экспорт
    successModal: { visible: false, pdfPath: '' },
    lastExportedPdf: '',
    lastExportSendsToast: '',
    // Обновление плагина с GitHub: процесс виден в шапке (спиннер) и тостах.
    updateStatus: { checking: false, stage: '', percent: 0, message: '' },
  }),

  getters: {
    projectStore() {
      return useProjectStore()
    },
  },

  actions: {
    showToast(msg, type = 'success') {
      showToast(msg, type)
    },

    // --- Вкладки ---
    switchTab(tabId) {
      flushAutoSave()
      this.activeTab = tabId
      const scenes = useScenesStore()
      const stats = useStatsStore()
      if (tabId === 'tab-scenes') {
        scenes.refreshFromModel()
        this.stopStatsAutoRefresh()
      } else if (tabId === 'tab-stats') {
        stats.refresh()
        this.startStatsAutoRefresh()
      } else if (tabId === 'tab-project') {
        // «Общая длительность проекта» подтягивается из статистики
        this.stopStatsAutoRefresh()
        stats.refresh()
      } else {
        this.stopStatsAutoRefresh()
      }
    },
    startStatsAutoRefresh() {
      this.stopStatsAutoRefresh()
      statsAutoTimer = setInterval(() => {
        if (this.activeTab === 'tab-stats') useStatsStore().refresh()
      }, STATS_AUTO_REFRESH_MS)
    },
    stopStatsAutoRefresh() {
      if (statsAutoTimer) {
        clearInterval(statsAutoTimer)
        statsAutoTimer = null
      }
    },

    // --- Загрузка данных (getData → window.app.loadData) ---
    loadData(data) {
      if (!data) return
      // Язык применяем до всего остального
      const payloadLang = data.pdf_settings && data.pdf_settings.language
      setLocale(String(payloadLang || 'ru').toLowerCase() === 'en' ? 'en' : 'ru')

      if (data.plugin_version) {
        this.pluginVersion = String(data.plugin_version)
        document.title = `DN1Sup Export PDF 2 v${this.pluginVersion}`
      }

      const settings = useSettingsStore()
      settings.applyPayload(data.pdf_settings || {})
      settings.vipsAvailable = Boolean(data.vips_available)
      settings.apiTargets = Array.isArray(data.api_targets) ? data.api_targets.slice() : []

      const project = useProjectStore()
      project.applyPayload(data)

      const scenes = useScenesStore()
      scenes.applyPayload(data.scenes)

      const dirs = useDirectoriesStore()
      dirs.applyPayload(data.directories)

      const templates = useTemplatesStore()
      templates.applyPayload(data.pdf_settings || {})
      templates.onTemplateSetsUpdated({ sets: data.template_sets || [] })

      // Диалог открыт на «Страницах» — актуализируем список и эскизы
      if (this.activeTab === 'tab-scenes') scenes.refreshFromModel()

      // При открытии панели предлагаем создать артикул
      setTimeout(() => this.maybeOfferArticulCreation(), 300)
    },

    // --- Смена языка (тумблер RU|EN в шапке) ---
    setLanguage(lang) {
      setLocale(lang)
      // Подписи осей графика формирует Ruby — перезапрашиваем отчёт,
      // если статистика сейчас открыта
      if (this.activeTab === 'tab-stats') useStatsStore().refresh()
      notifyChange()
    },

    // --- Артикул ---
    maybeOfferArticulCreation() {
      if (this.articulTypeModal.visible) return
      if (useProjectStore().articulValue) return
      this.articulTypeModal.visible = true
    },
    createProjectArticul(isCommercial) {
      const project = useProjectStore()
      const newArt = generateArticulLocal(isCommercial)
      project.setArticul(newArt)
      project.setTrade(isCommercial ? '1' : '0')
      this.articulTypeModal.visible = false
      callRuby('createProjectFolder', JSON.stringify({ articul: newArt, commercial: isCommercial }))
    },
    openArticulPrompt(action) {
      const project = useProjectStore()
      this.articulPrompt.value = generateArticulLocal(project.trade === '1')
      this.articulPrompt.action = action
      this.articulPrompt.visible = true
    },
    closeArticulPrompt() {
      this.articulPrompt.visible = false
      this.articulPrompt.action = null
    },
    confirmArticulPrompt() {
      const project = useProjectStore()
      const val = String(this.articulPrompt.value || '').trim()
      if (!val) {
        showToast(t('toast.articulEnter'), 'warning')
        return
      }
      project.setArticul(val)
      const action = this.articulPrompt.action
      this.closeArticulPrompt()
      if (action === 'export') this.beginExportFlow()
      else if (action === 'save') this.executeForcedSave()
    },

    // --- Экспорт ---
    startExport() {
      if (!useProjectStore().articulValue) {
        this.openArticulPrompt('export')
        return
      }
      this.beginExportFlow()
    },
    beginExportFlow() {
      const data = collectFormData()
      const enabledScenes = (data.scenes || []).filter((s) => s.enabled && s.page_type !== 'skip')
      if (enabledScenes.length === 0) {
        showToast(t('toast.selectSceneForExport'), 'error')
        return
      }
      const project = useProjectStore()
      const currRevNum = parseInt(project.workflow.revision, 10) || 1
      const nextRevNum = currRevNum + 1
      this.revisionModal.dateTime = nowStamp()
      this.revisionModal.currRev = `r${String(currRevNum).padStart(3, '0')}`
      this.revisionModal.nextRev = `r${String(nextRevNum).padStart(3, '0')}`
      this.revisionModal.note = ''
      this.revisionModal.visible = true
    },
    cancelRevision() {
      this.revisionModal.visible = false
    },
    skipRevision() {
      this.revisionModal.visible = false
      this.executeExport()
    },
    confirmRevision() {
      const project = useProjectStore()
      const rawNote = String(this.revisionModal.note || '').trim()
      if (!rawNote) {
        showToast(t('toast.revisionNoteRequired'), 'warning')
        return
      }
      const note = rawNote.replace(/\r?\n+/g, '; ')
      const exactTime = this.revisionModal.dateTime || nowStamp()
      const currRevNum = parseInt(project.workflow.revision, 10) || 1
      const nextRevNum = currRevNum + 1
      const nextRevStr = String(nextRevNum).padStart(3, '0')
      const currVerStr = String(parseInt(project.workflow.version, 10) || 1).padStart(2, '0')

      // Новая запись в историю (ревизия — отдельным полем, не в тексте)
      project.history.unshift({
        data: exactTime,
        date: exactTime,
        edit: note,
        text: note,
        description: note,
        pdf_link: '',
        ver: currVerStr,
        rev: nextRevStr,
      })
      project.workflow.revision = nextRevStr
      project.lastEdit = note
      project.syncHistoryEditPairs()

      this.revisionModal.visible = false
      this.executeExport()
    },
    executeExport() {
      const data = collectFormData()
      this.progress.percent = 0
      this.progress.message = t('progress.init')
      this.progress.visible = true
      callRuby('startExport', JSON.stringify(data))
    },
    updateProgress(percent, message) {
      this.progress.percent = percent
      if (message) this.progress.message = message
    },
    onExportSuccess(pdfPath, newRevision, lastPdfPath, lastSkpPath) {
      this.progress.visible = false
      // Открыта копия «_last» рядом с .skp — она первична для пользователя
      this.lastExportedPdf = lastPdfPath || pdfPath
      this.successModal.pdfPath = this.lastExportedPdf
      this.successModal.visible = true
      const project = useProjectStore()
      project.stampHistoryPdfLink(pdfPath)
      if (lastSkpPath) project.stampHistorySkpLink(lastSkpPath)
      if (newRevision !== undefined && newRevision !== null && newRevision !== '') {
        project.workflow.revision = String(newRevision)
      }
    },
    onExportError(errorMsg) {
      this.progress.visible = false
      showToast(t('toast.exportError', { msg: errorMsg }), 'error')
    },
    openExportedPdfFolder() {
      if (this.lastExportedPdf) callRuby('openFolder', this.lastExportedPdf)
    },

    // --- Сохранение / импорт / экспорт YAML ---
    forcedSave() {
      if (!useProjectStore().articulValue) {
        this.openArticulPrompt('save')
        return
      }
      this.executeForcedSave()
    },
    executeForcedSave() {
      callRuby('saveProjectYaml', JSON.stringify(collectFormData()))
    },
    importYaml() {
      callRuby('importYaml')
    },
    exportYaml() {
      callRuby('exportYaml', JSON.stringify(collectFormData()))
    },
    copyPdfPath() {
      const text = String(this.successModal.pdfPath || '').trim()
      if (!text) return
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(
          () => showToast(t('toast.pdfPathCopied'), 'success'),
          () => showToast(text, 'info'),
        )
      } else {
        showToast(t('toast.fileInfo', { path: text }), 'info')
      }
    },

    // --- Отправка проекта (вкладка «Отправка») ---
    startSend() {
      if (!useProjectStore().articulValue) {
        showToast(t('toast.articulRequiredSend'), 'error')
        return
      }
      callRuby('startSend', JSON.stringify(collectFormData()))
    },

    // --- Обновление плагина только с GitHub ---
    // (кнопка «круг со стрелками» в шапке; этапы приходят из Ruby через
    // window.app.onUpdateStatus: checking → found → downloading →
    // installing → done | current | dismissed | error)
    checkUpdateFull() {
      if (this.updateStatus.checking) return
      this.updateStatus = { checking: true, stage: 'checking', percent: 0, message: '' }
      showToast(t('toast.checkingUpdate'), 'info')
      callRuby('check_update')
    },
    onUpdateStatus(payload) {
      const stage = String(payload && payload.stage ? payload.stage : '')
      if (!stage) return
      const cur = payload.current !== undefined && payload.current !== null ? String(payload.current) : ''
      const latest = payload.latest !== undefined && payload.latest !== null ? String(payload.latest) : ''
      switch (stage) {
        case 'checking':
          this.updateStatus = { checking: true, stage, percent: 0, message: '' }
          break
        case 'found':
          this.updateStatus = { checking: true, stage, percent: 0, message: '' }
          showToast(t('toast.updateFound', { cur, dev: latest }), 'info')
          break
        case 'downloading': {
          const pct = Math.max(0, Math.min(100, parseInt(payload.percent, 10) || 0))
          this.updateStatus = { checking: true, stage, percent: pct, message: '' }
          break
        }
        case 'installing':
          this.updateStatus = { checking: true, stage, percent: 100, message: '' }
          showToast(t('toast.updating'), 'info')
          break
        case 'done':
          this.updateStatus = { checking: false, stage, percent: 100, message: '' }
          showToast(t('toast.updateInstalled', { ver: latest || cur }), 'success')
          break
        case 'current':
          this.updateStatus = { checking: false, stage, percent: 0, message: '' }
          showToast(t('toast.noUpdates', { cur }), 'success')
          break
        case 'dismissed':
          this.updateStatus = { checking: false, stage, percent: 0, message: '' }
          break
        case 'error': {
          const msg = String(payload.message || '')
          const code = String(payload.code || '')
          this.updateStatus = { checking: false, stage, percent: 0, message: '' }
          if (code === 'github_unreachable') {
            showToast(t('toast.githubUnreachable', { msg }), 'error')
          } else if (code === 'dev_copy') {
            showToast(msg || t('toast.unknownError'), 'error')
          } else {
            showToast(msg ? t('toast.updateFailed', { msg }) : t('toast.unknownError'), 'error')
          }
          break
        }
        default:
          break
      }
    },
  },
})
