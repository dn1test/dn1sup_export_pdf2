// Автосейв: любое изменение данных (notifyChange) с дебаунсом 400 мс уходит
// в Ruby как saveData(silent) — память сессии; на диск пишет Ruby при явном
// сохранении/экспорте/закрытии. Индикатор в футере читает autosaveState.

import { reactive } from 'vue'
import { callRuby } from '../bridge/sketchup.js'
import { t } from '../i18n/index.js'
import { collectFormData } from '../bridge/payload.js'

export const autosaveState = reactive({ status: 'idle', label: '' })

let autoSaveTimer = null

export function updateAutosaveIndicator(status, label) {
  autosaveState.status = status
  autosaveState.label = label || ''
}

// Немедленная отсылка накопленных изменений (молча, в память сессии)
export function flushAutoSave() {
  if (autoSaveTimer) {
    clearTimeout(autoSaveTimer)
    autoSaveTimer = null
  }
  try {
    const formData = collectFormData()
    const payload = Object.assign({}, formData, { is_auto_save: true, silent: true })
    callRuby('saveData', JSON.stringify(payload))
  } catch (err) {
    console.error('flushAutoSave error:', err)
    updateAutosaveIndicator('error', t('footer.autosaveError'))
  }
}

export function triggerAutoSave() {
  updateAutosaveIndicator('saving', t('footer.autosaveSaving'))
  clearTimeout(autoSaveTimer)
  autoSaveTimer = setTimeout(flushAutoSave, 400)
}

// Вызывается любой мутацией данных, которую нужно сохранить
export function notifyChange() {
  triggerAutoSave()
}

// Ruby подтвердил автосейв (колбэк saveData silent)
export function handleAutoSaved(yamlName) {
  const timeStr = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })
  const label = yamlName ? t('toast.savedMemory', { name: yamlName }) : t('toast.savedTime', { time: timeStr })
  updateAutosaveIndicator('saved', label)
}

export function pendingAutoSave() {
  return autoSaveTimer !== null
}
