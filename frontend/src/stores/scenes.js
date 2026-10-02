// Вкладка «Страницы»: список сцен проекта, эскизы (base64 от Ruby),
// выделение строки, постраничные настройки кадра и синхронизация
// safe-frame оверлея в SketchUp.

import { defineStore } from 'pinia'
import { callRuby } from '../bridge/sketchup.js'
import { notifyChange } from './autosave.js'
import { useTemplatesStore } from './templates.js'
import { useSettingsStore } from './settings.js'

const VALID_ASPECT_RATIOS = ['page', '16:9', '4:3', '3:2', '5:4', '1:1', '4:5', 'custom']

export const useScenesStore = defineStore('scenes', {
  state: () => ({
    scenes: [],
    thumbnails: {},
    selectedSceneIndex: 0,
    thumbsRequested: false,
    thumbsInFlight: false,
    thumbsSig: null,
    thumbsManual: false,
  }),

  getters: {
    activeCount(state) {
      return state.scenes.filter((s) => s.enabled !== false && s.page_type !== 'skip').length
    },
    totalCount(state) {
      return state.scenes.length
    },
    backgroundAll(state) {
      return state.scenes.some((s) => s.viewport_background === true)
    },
    watermarksAll(state) {
      return state.scenes.some((s) => s.viewport_watermarks === true)
    },
    frameAll(state) {
      return state.scenes.length > 0 && state.scenes.every((s) => s.frame_overlay === true)
    },
    selectedScene(state) {
      return state.scenes[state.selectedSceneIndex] || null
    },
  },

  actions: {
    applyPayload(scenes) {
      if (Array.isArray(scenes)) this.scenes = scenes
      if (this.selectedSceneIndex >= this.scenes.length) {
        this.selectedSceneIndex = Math.max(0, this.scenes.length - 1)
      }
    },

    thumbUrl(item, index) {
      const key = item.name || item.original_name || ''
      return item.thumbnail || this.thumbnails[key] || this.thumbnails[item.original_name] || this.thumbnails[index]
    },

    // --- Эскизы: перегенерация только при изменении состава страниц ---
    thumbsSignature() {
      return JSON.stringify(
        this.scenes.map((s) => [s.name || '', s.original_name || '', s.viewport_background === true, s.viewport_watermarks === true]),
      )
    },
    requestThumbnails(force) {
      if (this.thumbsInFlight) return
      const sig = this.thumbsSignature()
      if (!force && this.thumbsRequested && sig === this.thumbsSig) return
      this.thumbsRequested = true
      this.thumbsInFlight = true
      callRuby('getSceneThumbnails')
    },
    onThumbnailsLoaded(thumbs) {
      this.thumbsInFlight = false
      const got = thumbs && typeof thumbs === 'object' && Object.keys(thumbs).length > 0
      if (got) this.thumbnails = { ...this.thumbnails, ...thumbs }
      this.thumbsSig = this.thumbsSignature()
      if (this.thumbsManual) {
        this.thumbsManual = false
        // Тосты показывает вызывающий слой (bridge) — здесь только сброс флага
      }
      return got
    },
    onScenesRefreshed(scenes) {
      if (Array.isArray(scenes)) {
        this.scenes = scenes
        if (this.selectedSceneIndex >= scenes.length) {
          this.selectedSceneIndex = Math.max(0, scenes.length - 1)
        }
      }
      this.requestThumbnails(false)
    },
    refreshFromModel() {
      if (window.sketchup && typeof window.sketchup.refreshScenes === 'function') {
        callRuby('refreshScenes')
      } else {
        this.requestThumbnails(true)
      }
    },

    // --- Оверлей кадра в SketchUp ---
    syncSceneOverlay(scene, overrideRatio, isUserAction = false) {
      if (!scene) {
        scene = this.scenes[this.selectedSceneIndex || 0]
        if (!scene) return
      }
      let ratio = overrideRatio || scene.aspect_ratio || ''
      ratio = String(ratio).trim()
      if (!VALID_ASPECT_RATIOS.includes(ratio)) ratio = '4:3'
      if (!isUserAction) return
      const settings = useSettingsStore()
      // Write-through обязателен: иначе отложенный автосейв отправит
      // устаревший глобальный image_aspect_ratio и перетрёт выбор в сессии Ruby
      settings.imageAspectRatio = ratio
      callRuby('updateAspectSettings', JSON.stringify({
        template_key: scene.page_type || 'cover',
        scene_name: scene.name || '',
        scene_index: this.selectedSceneIndex || 0,
        aspect_ratio: ratio,
        image_aspect_ratio: ratio,
        visible: true,
        scale_pct: scene.scale_pct || 100,
        page_size: (settings.pageSize || 'A3').toUpperCase(),
        page_layout: (settings.pageLayout || 'landscape').toLowerCase(),
        image_width: settings.effectiveRenderWidth,
        show_aspect_overlay: scene.frame_overlay === true,
      }))
    },

    switchToSketchupScene(scene, index) {
      if (!scene) return
      callRuby('selectScene', JSON.stringify({
        index: index !== undefined ? index : 0,
        name: scene.name || '',
        original_name: scene.original_name || '',
      }))
      this.syncSceneOverlay(scene, null, true)
    },

    // --- Действия строк таблицы ---
    focusScene(index, withTemplate = true) {
      const scene = this.scenes[index]
      if (!scene) return
      this.selectedSceneIndex = index
      const templates = useTemplatesStore()
      if (withTemplate) templates.select(scene.page_type || 'cover')
      this.switchToSketchupScene(scene, index)
    },
    setEnabled(index, on) {
      const s = this.scenes[index]
      if (!s) return
      s.enabled = on
      notifyChange()
    },
    setAllEnabled(on) {
      this.scenes.forEach((s) => (s.enabled = on))
      notifyChange()
    },
    nameCommitted(index) {
      const s = this.scenes[index]
      if (!s) return
      s.name = String(s.name || '').trim()
      notifyChange()
    },
    descCommitted(index) {
      const s = this.scenes[index]
      if (!s) return
      s.description = String(s.description || '').trim()
      notifyChange()
    },
    frameToggled(index, on) {
      const s = this.scenes[index]
      if (!s) return
      // Write-through обязателен: иначе автосохранение перетрёт флаг кадра
      // в сессии Ruby и при переключении страниц оверлей отключится
      s.frame_overlay = on
      this.selectedSceneIndex = index
      this.switchToSketchupScene(s, index)
      callRuby('toggleAspectOverlay', JSON.stringify({ enabled: on, scene_index: index }))
      if (on) this.syncSceneOverlay(s, null, true)
      notifyChange()
    },
    ratioPicked(index, val) {
      const s = this.scenes[index]
      if (!s) return
      s.aspect_ratio = val
      if (this.selectedSceneIndex === index) this.syncSceneOverlay(s, val, true)
      notifyChange()
    },
    scaleChanged(index, scale) {
      const s = this.scenes[index]
      if (!s) return
      s.scale_pct = scale
      const templates = useTemplatesStore()
      templates.updateBlockSlot('image_4_3', { scale_pct: scale })
      if (this.selectedSceneIndex === index) this.syncSceneOverlay(s, null, true)
      notifyChange()
    },
    alignPicked(index, h, v) {
      const s = this.scenes[index]
      if (!s) return
      s.align_h = h
      s.align_v = v
      notifyChange()
    },
    pageTypeChanged(index, val) {
      const s = this.scenes[index]
      if (!s) return
      s.page_type = val
      this.selectedSceneIndex = index
      const templates = useTemplatesStore()
      templates.select(val)
      this.switchToSketchupScene(s, index)
      notifyChange()
    },
    commitReorder(from, to) {
      const [item] = this.scenes.splice(from, 1)
      this.scenes.splice(to, 0, item)
      this.scenes.forEach((s, idx) => (s.order = idx))
      notifyChange()
    },
    applyTemplateToAll() {
      const tpl = this.scenes[0] && this.scenes[0].page_type
      if (!tpl) return
      this.scenes.forEach((s) => (s.page_type = tpl))
      notifyChange()
    },
    // Глобальный фон: на все страницы + в блок шаблона, эскизы перегенерировать
    backgroundAllChanged(on) {
      this.scenes.forEach((s) => (s.viewport_background = on))
      const templates = useTemplatesStore()
      templates.updateBlockSlot('image_4_3', { show_background: on })
      this.requestThumbnails(true)
      notifyChange()
    },
    watermarksAllChanged(on) {
      this.scenes.forEach((s) => (s.viewport_watermarks = on))
      this.requestThumbnails(true)
      notifyChange()
    },
    frameAllChanged(on) {
      this.scenes.forEach((s) => (s.frame_overlay = on))
      callRuby('toggleAspectOverlay', JSON.stringify({ enabled: on, all: true }))
      notifyChange()
    },
    onActiveSceneChanged(index) {
      if (typeof index !== 'number' || index < 0 || index >= this.scenes.length) return
      if (this.selectedSceneIndex === index) return
      this.selectedSceneIndex = index
    },
  },
})
