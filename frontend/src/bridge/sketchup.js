// Мост JS↔Ruby. JS→Ruby: callRuby(action, param) → window.sketchup.<action>.
// Ruby→JS: registerRubyApi() вешает window.app.* — их дергает export_dialog.rb
// через execute_script. Контракт заморожен: имена и payload не меняются.

import { useAppStore } from '../stores/app.js'
import { useProjectStore } from '../stores/project.js'
import { useScenesStore } from '../stores/scenes.js'
import { useTemplatesStore } from '../stores/templates.js'
import { useDirectoriesStore } from '../stores/directories.js'
import { useSettingsStore } from '../stores/settings.js'
import { useStatsStore } from '../stores/stats.js'
import { handleAutoSaved, flushAutoSave } from '../stores/autosave.js'
import { showToast } from '../stores/toast.js'
import { t } from '../i18n/index.js'
import { mockRubyCall } from './mock.js'

export function callRuby(action, param) {
  if (window.sketchup && typeof window.sketchup[action] === 'function') {
    if (param !== undefined) window.sketchup[action](param)
    else window.sketchup[action]()
  } else {
    mockRubyCall(action, param)
  }
}

// Пульс активности: мышь/клавиатура/колесо → Ruby activityPing (троттлинг 30 с)
function bindActivityHeartbeat() {
  if (window.__activityHeartbeatBound) return
  window.__activityHeartbeatBound = true
  let lastPing = 0
  const ping = () => {
    const now = Date.now()
    if (now - lastPing < 30000) return
    lastPing = now
    callRuby('activityPing')
  }
  ;['pointermove', 'pointerdown', 'keydown', 'wheel'].forEach((evt) => {
    document.addEventListener(evt, ping, { passive: true })
  })
}

// Number-инпуты не должны перехватывать колесо мыши (блокировали скролл панелей)
function bindWheelGuard() {
  if (window.__wheelGuardBound) return
  window.__wheelGuardBound = true
  document.addEventListener(
    'wheel',
    (e) => {
      if (e.target && e.target.tagName === 'INPUT' && e.target.type === 'number') e.target.blur()
    },
    { passive: true },
  )
}

export function registerRubyApi() {
  window.app = {
    loadData(data) {
      useAppStore().loadData(data)
    },

    showNotification(msg, type) {
      showToast(msg, type || 'success')
    },

    onAutoSaved(yamlName) {
      handleAutoSaved(yamlName)
    },

    // Нативная смена активной страницы в SketchUp — панель следует за моделью
    onActiveSceneChanged(index) {
      useScenesStore().onActiveSceneChanged(index)
    },

    updateAspectInfo() {
      // Параметры кадра живут в поповере таблицы страниц — отдельных бейджей нет
    },

    syncOverlayState(isActive) {
      useSettingsStore().showAspectOverlay = Boolean(isActive)
    },

    onProjectFolderCreated(folderPath, yamlSaved) {
      if (!folderPath) return
      showToast(
        (yamlSaved ? t('toast.folderCreated', { path: folderPath }) : t('toast.folderCreatedNoYaml', { path: folderPath })) +
          t('toast.folderCreatedSuffix'),
        'success',
      )
    },

    onCustomerIdGenerated(newCustomerId) {
      const project = useProjectStore()
      if (newCustomerId) {
        project.customer.id = newCustomerId
        showToast(t('toast.customerIdGenerated', { id: newCustomerId }), 'info')
      }
    },

    onDirectorySelected(index, chosenPath) {
      useDirectoriesStore().onDirectorySelected(parseInt(index, 10), chosenPath)
    },

    onFolderFilesLoaded(data) {
      useDirectoriesStore().onFolderFilesLoaded(data)
    },

    onScenesRefreshed(scenes) {
      useScenesStore().onScenesRefreshed(scenes)
    },

    onSceneThumbnailsLoaded(thumbs) {
      const scenes = useScenesStore()
      const wasManual = scenes.thumbsManual
      const got = scenes.onThumbnailsLoaded(thumbs)
      if (wasManual) {
        showToast(got ? t('toast.thumbsUpdated') : t('toast.thumbsFailed'), got ? 'success' : 'error')
      }
    },

    updateProgress(percent, message) {
      useAppStore().updateProgress(percent, message)
    },

    onExportSuccess(pdfPath, newRevision, lastPdfPath, lastSkpPath) {
      useAppStore().onExportSuccess(pdfPath, newRevision, lastPdfPath, lastSkpPath)
    },

    onExportError(errorMsg) {
      useAppStore().onExportError(errorMsg)
    },

    onTemplateSetsUpdated(payload) {
      useTemplatesStore().onTemplateSetsUpdated(payload)
    },

    onTemplateSetLoaded(payload) {
      useTemplatesStore().onTemplateSetLoaded(payload)
    },

    onUpdateCheckResult(res) {
      useAppStore().onUpdateCheckResult(res)
    },

    onDevUpdateResult(res) {
      useAppStore().onDevUpdateResult(res)
    },

    onWorkStats(payload) {
      useStatsStore().apply(payload)
    },

    setAspectRatio(ratio) {
      const VALID = ['page', '16:9', '4:3', '3:2', '5:4', '1:1', '4:5', 'custom']
      if (!VALID.includes(ratio)) ratio = '4:3'
      const scenes = useScenesStore()
      const templates = useTemplatesStore()
      const settings = useSettingsStore()
      const scene = scenes.scenes[scenes.selectedSceneIndex || 0]
      if (scene) scene.aspect_ratio = ratio
      templates.updateBlockSlot('image_4_3', { aspect_ratio: ratio })
      settings.imageAspectRatio = ratio
      scenes.syncSceneOverlay(scene, ratio, true)
      // Мост для JS-вызовов (внутренний)
    },

    refreshStats() {
      useStatsStore().refresh()
    },

    resetStats() {
      useStatsStore().reset()
    },

    syncCurrentTemplateOverlay(overrideRatio, isUserAction) {
      const scenes = useScenesStore()
      const templates = useTemplatesStore()
      const scene = scenes.scenes[scenes.selectedSceneIndex || 0]
      if (scene) {
        scenes.syncSceneOverlay(scene, overrideRatio, isUserAction)
        return
      }
      // Сцен нет — синх по блоку шаблона
      const tplKey = templates.currentKey || templates.defaultKey
      const cfg = templates.layouts[tplKey] || {}
      const img = cfg.image_4_3 || {}
      if (img.visible === false) {
        useSettingsStore().showAspectOverlay = false
        if (isUserAction) callRuby('toggleAspectOverlay', false)
        return
      }
      if (!isUserAction) return
      const settings = useSettingsStore()
      const VALID = ['page', '16:9', '4:3', '3:2', '5:4', '1:1', '4:5', 'custom']
      let ratio = overrideRatio || img.aspect_ratio || settings.imageAspectRatio || '4:3'
      ratio = String(ratio).trim()
      if (!VALID.includes(ratio)) ratio = '4:3'
      callRuby('updateAspectSettings', JSON.stringify({
        template_key: tplKey,
        aspect_ratio: ratio,
        image_aspect_ratio: ratio,
        custom_layouts: templates.layouts,
        page_size: settings.pageSize.toUpperCase(),
        page_layout: settings.pageLayout.toLowerCase(),
        image_width: settings.effectiveRenderWidth,
        show_aspect_overlay: true,
      }))
    },
  }
}

// Инициализация моста: вызвать один раз после монтирования приложения
export function initBridge() {
  registerRubyApi()
  bindActivityHeartbeat()
  bindWheelGuard()
  window.addEventListener('beforeunload', flushAutoSave)
  window.addEventListener('unload', flushAutoSave)
  // Запрос начальных данных у SketchUp (в браузере ответит мок)
  callRuby('getData')
}
