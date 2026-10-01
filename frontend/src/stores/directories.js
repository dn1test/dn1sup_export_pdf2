// Вкладка «Папки»: каталоги спецификаций с превью файлов (base64 от Ruby),
// скан-таймауты и двусторонний синк описаний с полями проекта.

import { defineStore } from 'pinia'
import { callRuby } from '../bridge/sketchup.js'
import { notifyChange } from './autosave.js'
import { showToast } from './toast.js'
import { t } from '../i18n/index.js'
import { useProjectStore } from './project.js'

let uidSeq = 1
const nextUid = () => 'dir-' + uidSeq++
const defaultPreview = () => ({ state: 'loading', files: [], count: 0 })
// Таймеры скан-таймаутов — вне реактивного состояния
const scanTimers = {}

function getFolderName(pathStr) {
  if (!pathStr || typeof pathStr !== 'string') return ''
  const clean = pathStr.replace(/\\/g, '/').replace(/\/+$/, '')
  const segments = clean.split('/').filter(Boolean)
  return segments.length > 0 ? segments[segments.length - 1] : ''
}

export const useDirectoriesStore = defineStore('directories', {
  state: () => ({
    // Карточки для UI: { uid, path, title, description, send_to_server, thumb_size, preview }
    list: [],
    // Кеш ответов Ruby: { [index]: payload } и { [path]: payload }
    folderFiles: {},
    folderFilesByPath: {},
  }),

  actions: {
    applyPayload(rawDirs) {
      // Нормализация к массиву объектов
      let dirs = rawDirs
      if (dirs && !Array.isArray(dirs) && typeof dirs === 'object') {
        dirs = Object.keys(dirs).map((k) => {
          const v = dirs[k] || {}
          const p = v.path || ''
          return { path: p, title: v.title || getFolderName(p) || k, description: v.description || '' }
        })
      }
      if (!Array.isArray(dirs)) dirs = []
      dirs = dirs.map((d) => ({
        path: (d && d.path) || '',
        title: (d && d.title) || '',
        description: (d && d.description) || '',
        send_to_server: !(d && d.send_to_server === false),
        thumb_size: ['small', 'medium', 'large'].includes(d && d.thumb_size) ? d.thumb_size : 'medium',
      }))
      this.syncSpecs(dirs)
      this.rebuildList(dirs)
    },

    // Копирует данные в карточки, сохраняя uid/превью для неизменённых путей,
    // и запускает сканирование папок.
    rebuildList(dirs) {
      const old = this.list
      this.list = dirs.map((d, index) => {
        const prev = old[index]
        const pathUnchanged = prev && prev.path === d.path
        return {
          uid: pathUnchanged ? prev.uid : nextUid(),
          ...d,
          preview: pathUnchanged ? prev.preview : defaultPreview(),
        }
      })
      this.list.forEach((entry, index) => {
        if (!entry.path) {
          entry.preview = { state: 'nopath', files: [], count: 0 }
          return
        }
        const cached =
          this.folderFiles[index] && this.folderFiles[index].path === entry.path
            ? this.folderFiles[index]
            : this.folderFilesByPath[entry.path]
        if (cached) {
          this.folderFiles[index] = cached
          this.renderPreview(index, cached)
        } else {
          this.scheduleScanTimeout(index)
          callRuby('getFolderFiles', JSON.stringify({ index, path: entry.path }))
        }
      })
    },

    // Двусторонний синк спецификаций: поля проекта ↔ описания папок по
    // ключевым словам в пути/заголовке (материалы, техника, замеры, инфо)
    syncSpecs(dirs = this.list) {
      const project = useProjectStore()
      dirs.forEach((d) => {
        if (!d || typeof d !== 'object') return
        const pathStr = (d.path || '').toLowerCase()
        const titleStr = (d.title || '').toLowerCase()
        const descVal = (d.description || '').trim()
        const descIsReal = descVal.length > 0 && descVal !== 'Дополнительное описание'

        if (pathStr.includes('материал') || pathStr.includes('фурнитур') ||
            titleStr.includes('материал') || titleStr.includes('фурнитур')) {
          if (descIsReal) {
            if (!String(project.project.materials || '').trim()) project.project.materials = descVal
          } else if (String(project.project.materials || '').trim()) {
            d.description = project.project.materials.trim()
          }
        } else if (pathStr.includes('техник') || pathStr.includes('подсветк') ||
                   titleStr.includes('техник') || titleStr.includes('подсветк')) {
          if (descIsReal) {
            if (!String(project.appliances || '').trim()) project.appliances = descVal
            if (!String(project.project.lighting || '').trim()) project.project.lighting = descVal
          } else {
            const comb = [project.appliances, project.project.lighting]
              .map((s) => String(s || '').trim()).filter(Boolean).join('; ')
            if (comb) d.description = comb
          }
        } else if (pathStr.includes('замер') || titleStr.includes('замер')) {
          if (descIsReal) project.taskDimensions = descVal
        } else if (pathStr.includes('инфо') || pathStr.includes('заказчик') ||
                   titleStr.includes('инфо') || titleStr.includes('заказчик')) {
          if (descIsReal) project.notes = descVal
        }
      })
    },

    // --- Скан-таймауты превью ---
    clearScanTimeout(index) {
      if (scanTimers[index]) {
        clearTimeout(scanTimers[index])
        delete scanTimers[index]
      }
    },
    scheduleScanTimeout(index) {
      this.clearScanTimeout(index)
      scanTimers[index] = setTimeout(() => {
        const entry = this.list[index]
        if (entry && entry.preview && entry.preview.state === 'loading') {
          entry.preview = { state: 'timeout', files: [], count: 0 }
        }
      }, 4500)
    },

    renderPreview(index, data) {
      this.clearScanTimeout(index)
      const entry = this.list[index]
      if (!entry) return
      if (!data.exists) {
        entry.preview = { state: 'missing', files: [], count: 0 }
        return
      }
      const files = data.files || []
      entry.preview = { state: files.length > 0 ? 'ready' : 'empty', files, count: files.length }
    },

    // --- Действия ---
    add() {
      this.syncSpecs()
      const nextNum = this.list.length + 1
      this.list.push({
        uid: nextUid(),
        path: '',
        title: `Раздел #${nextNum}`,
        description: 'Дополнительное описание',
        send_to_server: true,
        thumb_size: 'medium',
        preview: { state: 'nopath', files: [], count: 0 },
      })
      notifyChange()
      const newIndex = this.list.length - 1
      // Сразу открываем проводник для выбора папки новой карточки
      callRuby('selectDirectory', String(newIndex))
      return newIndex
    },

    refreshOne(index) {
      const entry = this.list[index]
      if (!entry || !entry.path) return false
      entry.preview = defaultPreview()
      delete this.folderFiles[index]
      if (entry.path) delete this.folderFilesByPath[entry.path]
      this.scheduleScanTimeout(index)
      callRuby('getFolderFiles', JSON.stringify({ index, path: entry.path }))
      return true
    },

    refreshAll() {
      if (this.list.length === 0) {
        showToast(t('dirs.toastNoDirs'), 'warning')
        return
      }
      let refreshed = 0
      this.list.forEach((d, index) => {
        if (this.refreshOne(index)) refreshed++
      })
      if (refreshed === 0) showToast(t('dirs.toastNoPaths'), 'warning')
      else showToast(t('dirs.toastRefreshed', { n: refreshed }), 'info')
    },

    // Коммит правок из карточек: синк спецификаций + автосейв
    commit() {
      this.syncSpecs()
      notifyChange()
    },

    move(from, to) {
      const [item] = this.list.splice(from, 1)
      this.list.splice(to, 0, item)
      this.commit()
    },
    remove(index) {
      this.list.splice(index, 1)
      this.commit()
    },

    onDirectorySelected(index, chosenPath) {
      const entry = this.list[index]
      if (!entry) return
      entry.path = chosenPath
      const autoName = getFolderName(chosenPath)
      if (autoName) entry.title = autoName
      entry.preview = defaultPreview()
      this.scheduleScanTimeout(index)
      callRuby('getFolderFiles', JSON.stringify({ index, path: chosenPath }))
      notifyChange()
      showToast(t('toast.folderSelected', { path: chosenPath }), 'info')
    },

    onFolderFilesLoaded(data) {
      if (!data) return
      this.folderFiles[data.index] = data
      if (data.path) this.folderFilesByPath[data.path] = data
      this.renderPreview(data.index, data)
    },

    openExplorer(entry) {
      if (entry.path) callRuby('openDirectoryPath', entry.path)
      else showToast(t('dirs.toastNoFolder'), 'warning')
    },
  },
})
