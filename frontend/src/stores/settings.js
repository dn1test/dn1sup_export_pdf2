// Настройки документа/PDF (pdf_settings без custom_layouts — те живут в
// templates-сторе) и адресаты API. Значения полей привязаны v-model напрямую,
// пользовательские действия дополнительно толкают оверлей кадра в SketchUp.

import { defineStore } from 'pinia'
import { callRuby } from '../bridge/sketchup.js'
import { notifyChange } from './autosave.js'

const VALID_ASPECT_RATIOS = ['page', '16:9', '4:3', '3:2', '5:4', '1:1', '4:5', 'custom']

function normScaleMult(v) {
  const s = String(v ?? '2.0')
  if (['auto', '0.5', '1', '1.0', '1.5', '2', '2.0', '2.5', '3', '3.0'].includes(s)) {
    if (s === '1.0') return '1'
    if (s === '2') return '2.0'
    if (s === '3') return '3.0'
    return s
  }
  return '2.0'
}

export const useSettingsStore = defineStore('settings', {
  state: () => ({
    layoutRenderMode: 'image',
    compressPdf: true,
    imageFormat: 'png',
    webpQuality: '85',
    saveLayoutFile: true,
    pageSize: 'A3',
    pageLayout: 'landscape',
    marginMm: 5,
    fontFamily: 'Sofia Sans Condensed',
    imageAspectRatio: '4:3',
    customRatioW: 16,
    customRatioH: 9,
    renderQuality: 'medium',
    scaleMultiplier: '2.0',
    annotationFontSize: 'auto',
    primaryColor: '#005EB0',
    autoOpenPdf: true,
    saveSkpBackup: true,
    antialias: true,
    showAspectOverlay: false,
    overlayBorderColor: '#FF0000',
    overlayBorderOpacity: 100,
    overlayMaskColor: '#0F172A',
    overlayMaskOpacity: 10,
    language: 'ru',
    // extras из getData
    vipsAvailable: false,
    apiTargets: [],
  }),

  getters: {
    // Разрешение рендера по длинной стороне листа: 96/150/300 dpi (зеркало
    // legacy getEffectiveRenderWidth)
    effectiveRenderWidth(state) {
      const val = String(state.renderQuality || '').toLowerCase().trim()
      const pageSz = (state.pageSize || 'A3').toUpperCase().trim()
      let dpi = 150
      if (val === 'low') dpi = 96
      else if (val === 'high') dpi = 300
      else if (val === 'medium') dpi = 150
      else if (parseFloat(val) > 100) return Math.round(parseFloat(val))
      const longInches = pageSz === 'A3' ? 16.535433 : 11.692913
      return Math.round(longInches * dpi)
    },

    // «auto» множитель подстраивается под режим рендера и формат листа
    effectiveScaleMultiplier(state) {
      const raw = state.scaleMultiplier
      if (raw === 'auto') {
        const renderMode = String(state.layoutRenderMode || 'image').toLowerCase()
        const pageSz = (state.pageSize || 'A3').toUpperCase().trim()
        if (renderMode === 'hybrid') return pageSz === 'A3' ? 0.63 : 0.42
        const qVal = this.effectiveRenderWidth
        let mult = 0.6
        if (qVal <= 1400) mult = 0.6
        else if (qVal <= 2000) mult = 0.9
        else if (qVal <= 2800) mult = 1.2
        else if (qVal <= 3400) mult = 1.5
        else mult = 1.8
        if (pageSz === 'A3') mult = Math.max(mult, 0.9)
        return Math.round(mult * 70) / 100
      }
      return parseFloat(raw) || 2.0
    },

    docFontFamily(state) {
      return state.fontFamily
    },
  },

  actions: {
    applyPayload(settings = {}) {
      this.layoutRenderMode = settings.layout_render_mode || 'image'
      this.compressPdf = settings.compress_pdf === true || settings.compress_pdf === 'compress'
      this.imageFormat = String(settings.image_format || 'png').toLowerCase()
      const wq = String(settings.webp_quality ?? '85').toLowerCase()
      this.webpQuality = ['75', '85', '95', 'lossless'].includes(wq) ? wq : '85'
      this.saveLayoutFile = settings.save_layout_file !== false
      this.pageSize = settings.page_size || 'A3'
      this.pageLayout = settings.page_layout || 'landscape'
      const marginMm =
        settings.margin_mm !== undefined && settings.margin_mm !== null
          ? parseFloat(settings.margin_mm)
          : settings.margin !== undefined && settings.margin !== null
            ? Math.round((parseFloat(settings.margin) * 25.4) / 72.0)
            : 5
      this.marginMm = marginMm
      let family = (settings.font_family || 'Sofia Sans Condensed').trim()
      if (family.toLowerCase().includes('din')) family = 'Oswald'
      this.fontFamily = family
      this.imageAspectRatio = VALID_ASPECT_RATIOS.includes(settings.image_aspect_ratio)
        ? settings.image_aspect_ratio
        : '4:3'
      this.customRatioW = parseFloat(settings.custom_ratio_w) || 16
      this.customRatioH = parseFloat(settings.custom_ratio_h) || 9
      let qVal = settings.render_quality ? String(settings.render_quality).toLowerCase().trim() : ''
      if (!['low', 'medium', 'high'].includes(qVal)) {
        const num = parseInt(settings.image_width, 10)
        if (num <= 1400) qVal = 'low'
        else if (num > 2800) qVal = 'high'
        else qVal = 'medium'
      }
      this.renderQuality = qVal
      this.scaleMultiplier = normScaleMult(
        settings.scale_multiplier !== undefined && settings.scale_multiplier !== null
          ? settings.scale_multiplier
          : settings.scale_factor
            ? settings.scale_factor
            : '2.0',
      )
      this.annotationFontSize = settings.annotation_font_size || 'auto'
      this.primaryColor = settings.primary_color ? `#${String(settings.primary_color).replace('#', '')}` : '#005EB0'
      this.autoOpenPdf = settings.auto_open_pdf !== false
      this.saveSkpBackup = settings.save_skp_backup !== false
      this.antialias = settings.antialias !== false
      this.showAspectOverlay = Boolean(settings.show_aspect_overlay)
      this.overlayBorderColor = settings.overlay_border_color || '#FF0000'
      this.overlayBorderOpacity = settings.overlay_border_opacity !== undefined ? settings.overlay_border_opacity : 100
      this.overlayMaskColor = settings.overlay_mask_color || '#0F172A'
      this.overlayMaskOpacity = settings.overlay_mask_opacity !== undefined ? settings.overlay_mask_opacity : 10
      this.syncDocFontVars()
    },

    // css-переменные печатного шрифта (превью в редакторе шаблонов)
    syncDocFontVars() {
      if (typeof document === 'undefined') return
      document.documentElement.style.setProperty('--page-font-family', `"${this.docFontFamily}", sans-serif`)
    },

    setMargin(mm) {
      const num = Math.max(0, Math.min(40, parseFloat(mm) || 0))
      this.marginMm = num
      notifyChange()
    },

    setFontFamily(val) {
      let family = (val || 'Sofia Sans Condensed').trim()
      if (family.toLowerCase().includes('din')) family = 'Oswald'
      this.fontFamily = family
      this.syncDocFontVars()
      notifyChange()
    },

    // Пользователь поменял параметр, влияющий на оверлей кадра в SketchUp
    aspectChanged() {
      callRuby('updateAspectSettings', JSON.stringify({
        image_aspect_ratio: this.imageAspectRatio,
        custom_ratio_w: parseFloat(this.customRatioW) || 16,
        custom_ratio_h: parseFloat(this.customRatioH) || 9,
        page_size: (this.pageSize || 'A3').toUpperCase(),
        page_layout: (this.pageLayout || 'landscape').toLowerCase(),
        image_width: this.effectiveRenderWidth,
      }))
      notifyChange()
    },
  },
})
