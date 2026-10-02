// Вкладка «Шаблоны»: реестр шаблонов страниц (custom_layouts), мастер-шаблон,
// наборы шаблонов, редактор параметров и модалка создания/правки параметра.
// Параметры шаблона — «сырые» источники данных с настройками размещения;
// подписи и превью вычисляются на лету (геттеры), мутации — через actions.

import { defineStore } from 'pinia'
import { callRuby } from '../bridge/sketchup.js'
import { notifyChange } from './autosave.js'
import { showToast } from './toast.js'
import { t, locale } from '../i18n/index.js'
import { useProjectStore } from './project.js'
import { useScenesStore } from './scenes.js'
import { useDirectoriesStore } from './directories.js'
import { previewDate, isoToRuDate } from '../lib/dates.js'

const tval = (v) => String(v === undefined || v === null ? '' : v).trim()

// Блок видового экрана по умолчанию (единый для всех шаблонов)
export const DEFAULT_IMAGE_SLOT = {
  x: 25.0, y: 12.0, w: 50.0, h: 82.0,
  visible: true,
  content: 'render_viewport',
  show_background: false,
  aspect_ratio: '4:3',
  scale_pct: 100,
}

// Структурный фолбэк для известных ключей (только значения по умолчанию)
export const DEFAULT_LAYOUTS = {
  cover: { name: 'Титульный лист (Cover)', image_4_3: { ...DEFAULT_IMAGE_SLOT, scale_pct: 80 } },
  description: { name: 'Описание и спецификации (Description)', image_4_3: { ...DEFAULT_IMAGE_SLOT, scale_pct: 70 } },
  explain: { name: 'Содержание и ведомость (Explain)', image_4_3: { ...DEFAULT_IMAGE_SLOT, scale_pct: 60 } },
  general: { name: 'Общий вид (General)', image_4_3: { ...DEFAULT_IMAGE_SLOT, aspect_ratio: '16:9' } },
  visual: { name: 'Визуализация (Visual)', image_4_3: { ...DEFAULT_IMAGE_SLOT, aspect_ratio: '16:9' } },
  blank: { name: 'Без шаблона (Blank)', image_4_3: { ...DEFAULT_IMAGE_SLOT, aspect_ratio: '16:9' } },
}

export const DEFAULT_PARAM_SETTINGS = { align: 'left', valign: 'top', font_size: 10, color: '#0F172A' }
export const PARAM_FONT_SIZES = [6, 7, 8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 48, 56, 64, 72]
export const PARAM_LINE_GAPS = [0, 1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10]

function deepClone(obj) {
  if (obj === null || typeof obj !== 'object') return obj
  if (Array.isArray(obj)) return obj.map(deepClone)
  const copy = {}
  for (const k of Object.keys(obj)) copy[k] = deepClone(obj[k])
  return copy
}

function isSlotVisible(slotObj, defaultVal = true) {
  if (!slotObj) return defaultVal
  const v = slotObj.visible
  if (v === false || v === 'false' || v === 0 || v === '0') return false
  if (v === true || v === 'true' || v === 1 || v === '1') return true
  return defaultVal
}

// Нормализация параметра шаблона (зеркало ProjectData#normalize_template_params)
export function normalizeTemplateParam(raw) {
  const p = raw && typeof raw === 'object' ? raw : {}
  const bool = (v, def) => (v === undefined || v === null) ? def : !(v === false || v === 'false' || v === 0 || v === '0')
  const num = (v, def, min, max) => {
    const n = parseFloat(v)
    return isNaN(n) ? def : Math.min(max, Math.max(min, n))
  }
  const alignRaw = tval(p.align)
  const valignRaw = tval(p.valign)
  const common = {
    id: tval(p.id),
    label: tval(p.label).replace(/:+\s*$/, '').trim(),
    show_label: bool(p.show_label, true),
    align: ['left', 'center', 'right'].includes(alignRaw) ? alignRaw : 'left',
    valign: ['top', 'center', 'bottom'].includes(valignRaw) ? valignRaw : 'top',
    font_size: num(p.font_size, DEFAULT_PARAM_SETTINGS.font_size, 4, 72),
    color: /^#[0-9a-fA-F]{6}$/.test(tval(p.color)) ? tval(p.color) : DEFAULT_PARAM_SETTINGS.color,
    visible: bool(p.visible, true),
  }

  if (p.group === true || p.group === 'true') {
    const children = Array.isArray(p.params) ? p.params : []
    const dirRaw = tval(p.direction)
    return Object.assign(common, {
      id: common.id || `g_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 7)}`,
      group: true,
      direction: dirRaw === 'vertical' ? 'vertical' : 'horizontal',
      show_label: bool(p.show_label, false),
      params: children
        .filter((c) => c && typeof c === 'object' && tval(c.source))
        .map((c) => ({
          id: tval(c.id) || `c_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 7)}`,
          source: tval(c.source),
          label: tval(c.label),
          show_label: bool(c.show_label, false),
        })),
    })
  }

  return Object.assign(common, {
    id: common.id || `p_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 7)}`,
    source: tval(p.source),
  })
}

function getFolderName(pathStr) {
  if (!pathStr || typeof pathStr !== 'string') return ''
  const clean = pathStr.replace(/\\/g, '/').replace(/\/+$/, '')
  const segments = clean.split('/').filter(Boolean)
  return segments.length > 0 ? segments[segments.length - 1] : ''
}

// Стадии в печатном формате чек-листа
function stadiaMark(st) {
  const done = !!(st && st.status)
  const name = tval(st && st.name)
  return `${done ? '[✓]' : '[ ]'} ${name}`
}
function histEntryText(e) {
  if (Array.isArray(e)) return `${tval(e[0])} ${tval(e[1])}`.trim()
  if (e && typeof e === 'object') {
    const d = tval(e.data || e.date)
    const txt = tval(e.edit || e.text || e.description)
    return `${d} ${txt}`.trim()
  }
  return tval(e)
}

// Живое значение источника для превью (зеркало InfoLineResolver#resolve_param)
export function paramPreviewValue(source) {
  const project = useProjectStore()
  const scenes = useScenesStore()
  const dirs = useDirectoriesStore()
  const info = {
    articul: project.project.articul,
    name_product: project.project.product,
    furniture_name: project.project.product,
    name_project: project.project.product,
    name_place: project.project.place,
    room_name: project.project.place,
    adress: project.project.adress,
    address: project.project.adress,
    company: project.project.name_company,
    materials: project.project.materials,
    lighting: project.project.lighting,
    customer_id: project.customer.id,
    name_customer: project.customer.name,
    phone: project.customer.phone,
    email: project.customer.email,
    price: project.workflow.price,
    start_date: project.workflow.start_date,
    end_date: project.workflow.end_date,
    total_duration: project.workflow.total_duration,
    rate: project.workflow.rate,
    version: project.workflow.version,
    revision: project.workflow.revision,
    status: project.workflow.status,
    stadia: project.workflow.stadia,
    history_edit: project.workflow.history_edit,
    last_edit: project.lastEdit,
  }
  const wf = project.workflow
  const s = tval(source)
  switch (s) {
    case 'project.articul': return tval(info.articul)
    case 'project.furniture_name': return tval(info.furniture_name || info.name_product)
    case 'project.room_name': return tval(info.room_name || info.name_place)
    case 'project.address': return tval(info.address || info.adress)
    case 'project.company': return tval(info.company)
    case 'project.materials': return tval(info.materials)
    case 'project.lighting': return tval(info.lighting)
    case 'customer.id': return tval(info.customer_id)
    case 'customer.name': return tval(info.name_customer)
    case 'customer.name_or_company':
      return project.trade === '1' ? tval(info.company) : tval(info.name_customer)
    case 'customer.phone': return tval(info.phone)
    case 'customer.email': return tval(info.email)
    case 'workflow.author': return tval(wf.author)
    case 'workflow.price': {
      const v = tval(info.price)
      return v ? `${v} руб.` : ''
    }
    case 'workflow.start_date': return isoToRuDate(tval(info.start_date))
    case 'workflow.end_date': return isoToRuDate(tval(info.end_date))
    case 'workflow.duration': {
      const d = tval(info.total_duration)
      return d ? (/дн|день|час/i.test(d) ? d : `${d} дн.`) : ''
    }
    case 'workflow.rate': return tval(wf.rate)
    case 'workflow.version': return `v${tval(wf.version) || '01'}`
    case 'workflow.revision': return `#r${tval(wf.revision) || '001'}`
    case 'workflow.version_rev': return `${String(tval(wf.version) || '01').padStart(2, '0')}#${String(tval(wf.revision) || '001').padStart(3, '0')}`
    case 'workflow.date': return previewDate(wf.date_order || info.date)
    case 'workflow.status': return tval(wf.status)
    case 'workflow.stadia': {
      const arr = Array.isArray(wf.stadia) && wf.stadia.length > 0 ? wf.stadia : null
      return arr ? arr.map(stadiaMark).join('\n') : tval(wf.status)
    }
    case 'workflow.last_edit': {
      const h = wf.history_edit
      if (Array.isArray(h) && h.length > 0) return histEntryText(h[0])
      return tval(info.last_edit)
    }
    case 'workflow.history': {
      const h = wf.history_edit
      return Array.isArray(h) ? h.map(histEntryText).filter(Boolean).join('\n') : tval(info.last_edit)
    }
    case 'scene.name': {
      const sc = scenes.scenes[scenes.selectedSceneIndex] ||
        scenes.scenes.find((x) => x.page_type === currentTemplateKeySafe()) || scenes.scenes[0] || null
      return tval(sc && (sc.name || sc.original_name))
    }
    case 'scene.description': {
      const sc = scenes.scenes[scenes.selectedSceneIndex] ||
        scenes.scenes.find((x) => x.page_type === currentTemplateKeySafe()) || scenes.scenes[0] || null
      return tval(sc && sc.description)
    }
    case 'page.number_total': return t('auto.page.numberPreview')
    case 'page.toc': {
      const list = scenes.scenes.filter((x) => x.enabled !== false)
      return list.length > 0 ? list.map((x, i) => `${i + 1}. ${x.name}`).join('\n') : ''
    }
    default: {
      const m = s.match(/^dir\.(\d+)\.(title|description|line)$/)
      if (m) {
        const d = dirs.list[parseInt(m[1], 10)]
        if (!d) return ''
        if (m[2] === 'line') return [tval(d.title), tval(d.description)].filter(Boolean).join('\n')
        return tval(d[m[2] === 'title' ? 'title' : 'description'])
      }
      return ''
    }
  }
}

function currentTemplateKeySafe() {
  try {
    const templates = useTemplatesStore()
    return templates.currentKey
  } catch (e) {
    return ''
  }
}

// Группы источников для модалки параметра (подписи — словарь текущей локали)
export function buildParamSources() {
  const dirs = useDirectoriesStore()
  const groups = [
    { title: t('srcGroup.projectPassport'), options: [
      { value: 'project.articul', label: t('src.project.articul') },
      { value: 'project.furniture_name', label: t('src.project.furniture_name') },
      { value: 'project.room_name', label: t('src.project.room_name') },
      { value: 'project.address', label: t('src.project.address') },
      { value: 'project.materials', label: t('src.project.materials') },
      { value: 'project.lighting', label: t('src.project.lighting') },
    ] },
    { title: t('srcGroup.projectCustomer'), options: [
      { value: 'customer.id', label: t('src.customer.id') },
      { value: 'customer.name', label: t('src.customer.name') },
      { value: 'project.company', label: t('src.project.company') },
      { value: 'customer.name_or_company', label: t('src.customer.name_or_company') },
      { value: 'customer.phone', label: t('src.customer.phone') },
      { value: 'customer.email', label: t('src.customer.email') },
    ] },
    { title: t('srcGroup.projectWorkflow'), options: [
      { value: 'workflow.author', label: t('src.workflow.author') },
      { value: 'workflow.price', label: t('src.workflow.price') },
      { value: 'workflow.start_date', label: t('src.workflow.start_date') },
      { value: 'workflow.end_date', label: t('src.workflow.end_date') },
      { value: 'workflow.duration', label: t('src.workflow.duration') },
      { value: 'workflow.rate', label: t('src.workflow.rate') },
      { value: 'workflow.version_rev', label: t('src.workflow.version_rev') },
      { value: 'workflow.date', label: t('src.workflow.date') },
      { value: 'workflow.status', label: t('src.workflow.status') },
      { value: 'workflow.stadia', label: t('src.workflow.stadia') },
      { value: 'workflow.last_edit', label: t('src.workflow.last_edit') },
      { value: 'workflow.history', label: t('src.workflow.history') },
    ] },
    { title: t('srcGroup.scene'), options: [
      { value: 'scene.name', label: t('src.scene.name') },
      { value: 'scene.description', label: t('src.scene.description') },
    ] },
    { title: t('srcGroup.page'), options: [
      { value: 'page.number_total', label: t('src.page.number_total') },
      { value: 'page.toc', label: t('src.page.toc') },
    ] },
  ]
  const dirOptions = []
  dirs.list.forEach((d, idx) => {
    if (!d) return
    const dirTitle = tval(d.title) || getFolderName(d.path) || t('src.dir.section', { n: idx + 1 })
    dirOptions.push({ value: `dir.${idx}.line`, label: `📁 ${dirTitle}` })
  })
  if (dirOptions.length > 0) groups.splice(3, 0, { title: t('srcGroup.directories'), options: dirOptions })
  return groups
}

// Человекочитаемое название источника
export function paramSourceLabel(source) {
  const dirs = useDirectoriesStore()
  const s = tval(source)
  const m = s.match(/^dir\.(\d+)\.(title|description|line)$/)
  if (m) {
    const idx = parseInt(m[1], 10)
    const d = dirs.list[idx]
    const dirTitle = (d && (tval(d.title) || getFolderName(d.path))) || t('src.dir.section', { n: idx + 1 })
    if (m[2] === 'line') return `📁 ${dirTitle}`
    return m[2] === 'title'
      ? t('src.dir.titleSuffix', { name: dirTitle })
      : t('src.dir.descSuffix', { name: dirTitle })
  }
  for (const g of buildParamSources()) {
    const opt = g.options.find((o) => o.value === s)
    if (opt) return opt.label
  }
  // Источник отсутствует в списке (legacy, напр. workflow.version/revision) — берём подпись из словаря
  const legacy = t(`src.${s}`)
  if (legacy !== `src.${s}`) return legacy
  return s || '—'
}

// Эффективная подпись параметра: заданный label, иначе авто-подпись источника
export function effectiveParamLabel(source, label) {
  const project = useProjectStore()
  const dirs = useDirectoriesStore()
  const l = tval(label).replace(/:+\s*$/, '').trim()
  if (l) return l
  const s = tval(source)
  if (s === 'customer.name_or_company') {
    return project.trade === '1'
      ? t('auto.customer.name_or_company.company')
      : t('auto.customer.name_or_company.customer')
  }
  const auto = t(`auto.${s}`)
  if (auto !== `auto.${s}`) return auto
  const m = s.match(/^dir\.(\d+)\.(title|description|line)$/)
  if (m) {
    if (m[2] === 'line') return ''
    const idx = parseInt(m[1], 10)
    const d = dirs.list[idx]
    const base = (d && (tval(d.title) || getFolderName(d.path))) || t('src.dir.section', { n: idx + 1 })
    return m[2] === 'title' ? t('src.dir.titleSuffix', { name: base }) : t('src.dir.descSuffix', { name: base })
  }
  return ''
}

// Название зоны размещения параметра
export function paramZoneLabel(p) {
  const h = t(p.align === 'center' ? 'zone.h.center' : (p.align === 'right' ? 'zone.h.right' : 'zone.h.left'))
  const v = t(p.valign === 'bottom' ? 'zone.v.bottom' : (p.valign === 'center' ? 'zone.v.center' : 'zone.v.top'))
  return `${h} ${v}`
}

function formatTemplateSetDate(raw) {
  const s = String(raw || '').trim()
  if (!s) return ''
  const d = new Date(s)
  if (isNaN(d.getTime())) return s
  const p = (n) => String(n).padStart(2, '0')
  return `${p(d.getDate())}.${p(d.getMonth() + 1)}.${d.getFullYear()}`
}

export const useTemplatesStore = defineStore('templates', {
  state: () => ({
    layouts: {},            // custom_layouts
    currentKey: '',         // выбранный шаблон в редакторе
    masterKey: '',
    masterEnabled: false,
    sets: [],               // [{ name, saved_at, templates_count }]
    modals: {
      newTemplate: null,    // { name, description, base, bases }
      renameTemplate: null, // { key, name, description }
      deleteTemplate: null, // { key, name }
      saveSet: null,        // { name }
      confirmSet: null,     // { type, name, title, msg, danger }
    },
    paramModal: { visible: false, mode: 'create', id: null, tplKey: '', source: '', label: '' },
  }),

  getters: {
    // Все шаблоны равнозначны; имена legacy-записей — из DEFAULT_LAYOUTS
    allTemplates(state) {
      return Object.keys(state.layouts).map((key) => {
        const tpl = state.layouts[key] || {}
        const name = tpl._name || tpl.name ||
          (DEFAULT_LAYOUTS[key] && DEFAULT_LAYOUTS[key].name) ||
          t('tpl.fallbackName', { key })
        return {
          key,
          name,
          description: tpl._description || tpl.description || '',
          baseType: tpl._base_type || (DEFAULT_LAYOUTS[key] ? key : 'general'),
        }
      })
    },

    currentDef(state) {
      const custom = state.layouts[state.currentKey] || {}
      const key = state.currentKey
      const baseKey = custom._base_type || (DEFAULT_LAYOUTS[key] ? key : 'general')
      const name = custom._name || custom.name ||
        (DEFAULT_LAYOUTS[key] && DEFAULT_LAYOUTS[key].name) ||
        t('tpl.fallbackName', { key })
      return {
        key,
        name,
        description: custom._description || custom.description || '',
        baseType: baseKey,
        image_def: (DEFAULT_LAYOUTS[baseKey] || DEFAULT_LAYOUTS.general).image_4_3 || DEFAULT_IMAGE_SLOT,
      }
    },

    defaultKey(state) {
      return Object.keys(state.layouts)[0] || 'cover'
    },

    // Живой список параметров выбранного шаблона
    currentParams(state) {
      const cfg = state.layouts[state.currentKey] || {}
      return Array.isArray(cfg.params) ? cfg.params : []
    },

    lineSettings(state) {
      const cfg = state.layouts[state.currentKey] || {}
      const num = (v, def, min, max) => {
        const n = parseFloat(v)
        return isNaN(n) ? def : Math.min(max, Math.max(min, n))
      }
      const raw = cfg.line_enabled
      return {
        line_gap: num(cfg.line_gap, 2.5, 0, 50),
        line_enabled: raw !== undefined && raw !== null && !(raw === false || raw === 'false' || raw === 0 || raw === '0'),
      }
    },

    // Список для сайдбара: подписи использования с плюрализацией
    sidebarList() {
      const scenes = useScenesStore()
      const isMaster = this.masterEnabled && this.masterKey
      return this.allTemplates.map((tpl) => {
        const matching = scenes.scenes.filter((s) => s.page_type === tpl.key)
        let usageText = ''
        if (matching.length > 0) {
          usageText = locale.value === 'en'
            ? t('tpl.usageScene1', { n: matching.length })
            : t(
                matching.length === 1 ? 'tpl.usageScene1' : matching.length < 5 ? 'tpl.usageScene2' : 'tpl.usageScene5',
                { n: matching.length },
              )
        } else {
          usageText = t('tpl.notUsed')
        }
        return {
          key: tpl.key,
          name: tpl.name,
          description: tpl.description,
          sub: tpl.description || usageText,
          usageText,
          active: tpl.key === this.currentKey,
          master: isMaster && tpl.key === this.masterKey,
        }
      })
    },

    // Опции селекта «Шаблон» в таблице страниц (cover — признак обложки)
    sceneOptions() {
      return this.allTemplates.map((tpl) => ({
        key: tpl.key,
        name: tpl.name,
        description: tpl.description || '',
        cover: tpl.baseType === 'cover' || tpl.key === 'cover',
      }))
    },

    // Бейдж привязки текущего шаблона к сценам
    usageBadge() {
      const scenes = useScenesStore()
      const matching = scenes.scenes.filter((s) => s.page_type === this.currentKey)
      if (matching.length > 0) {
        const names = matching.map((s) => s.name).join(', ')
        return { text: t('tpl.usageScenes', { names }), title: t('tpl.usageScenesTitle', { names }), empty: false }
      }
      return { text: t('tpl.usageEmpty'), title: t('tpl.usageEmptyTitle'), empty: true }
    },

    setsView(state) {
      return state.sets.map((set) => {
        const count = set.templates_count || 0
        const dateStr = formatTemplateSetDate(set.saved_at)
        let word
        if (locale.value === 'en') word = count === 1 ? t('tpl.setWord1', { n: count }) : t('tpl.setWord5', { n: count })
        else if (count === 1) word = t('tpl.setWord1', { n: count })
        else word = count > 1 && count < 5 ? t('tpl.setWord2', { n: count }) : t('tpl.setWord5', { n: count })
        return { name: set.name, sub: `${count} ${word}${dateStr ? ` · ${dateStr}` : ''}` }
      })
    },

    // Снимок параметров редактора с вычисленными подписями и превью
    editorView() {
      const decorateChild = (c) => ({
        ...c,
        _label: paramSourceLabel(c.source),
        _shownLabel: c.show_label ? effectiveParamLabel(c.source, c.label) : '',
        _preview: paramPreviewValue(c.source).replace(/\n+/g, ' ⏎ '),
      })
      const decorate = (p) => ({
        ...p,
        _label: p.group ? '' : paramSourceLabel(p.source),
        _shownLabel: p.show_label ? effectiveParamLabel(p.source, p.label) : '',
        _preview: p.group ? '' : paramPreviewValue(p.source).replace(/\n+/g, ' ⏎ '),
        _zone: paramZoneLabel(p),
        _children: Array.isArray(p.params) ? p.params.map(decorateChild) : [],
      })
      return this.currentParams.map(decorate)
    },

    // Превью и подсказка модалки параметра — всегда актуальны
    paramModalPreview(state) {
      const val = paramPreviewValue(state.paramModal.source).replace(/\n+/g, ' ⏎ ')
      return {
        text: val ? t('pm.previewExample', { value: val }) : t('pm.previewEmpty'),
        empty: !val,
      }
    },
    paramModalLabelPlaceholder(state) {
      const auto = effectiveParamLabel(state.paramModal.source, '')
      return auto ? t('pm.labelAutoPh', { auto }) : t('pm.labelNoAutoPh')
    },
    paramModalSources() {
      return buildParamSources()
    },
  },

  actions: {
    // --- Нормализация конфигов (чистка старых ключей, дефолты слотов) ---
    ensureLayouts() {
      const metaKeys = new Set(['name', '_name', 'description', '_description', '_base_type', '_icon', '_meta'])
      Object.keys(this.layouts).forEach((tplKey) => {
        const cfg = this.layouts[tplKey]
        if (!cfg || typeof cfg !== 'object') {
          this.layouts[tplKey] = {}
          return
        }
        Object.keys(cfg).forEach((k) => {
          if (k !== 'image_4_3' && k !== 'params' && k !== 'line_gap' && k !== 'line_enabled' && !metaKeys.has(k)) {
            delete cfg[k]
          }
        })
        const baseKey = cfg._base_type || (DEFAULT_LAYOUTS[tplKey] ? tplKey : 'general')
        const defImg = (DEFAULT_LAYOUTS[tplKey] || DEFAULT_LAYOUTS[baseKey] || DEFAULT_LAYOUTS.general).image_4_3 || DEFAULT_IMAGE_SLOT
        if (!cfg.image_4_3 || typeof cfg.image_4_3 !== 'object') {
          cfg.image_4_3 = deepClone(defImg)
        } else {
          cfg.image_4_3.visible = isSlotVisible(cfg.image_4_3)
          if (!cfg.image_4_3.content) cfg.image_4_3.content = defImg.content || 'render_viewport'
          if (!cfg.image_4_3.aspect_ratio) cfg.image_4_3.aspect_ratio = defImg.aspect_ratio || '4:3'
          if (cfg.image_4_3.scale_pct === undefined) cfg.image_4_3.scale_pct = defImg.scale_pct !== undefined ? defImg.scale_pct : 100
          if (cfg.image_4_3.x === undefined) cfg.image_4_3.x = defImg.x
          if (cfg.image_4_3.y === undefined) cfg.image_4_3.y = defImg.y
          if (cfg.image_4_3.w === undefined) cfg.image_4_3.w = defImg.w
          if (cfg.image_4_3.h === undefined) cfg.image_4_3.h = defImg.h
        }
        if (!Array.isArray(cfg.params)) {
          cfg.params = []
        } else {
          cfg.params = cfg.params
            .filter((p) => p && typeof p === 'object' && (p.group === true || p.group === 'true' || tval(p.source)))
            .map(normalizeTemplateParam)
        }
        const rawGap = parseFloat(cfg.line_gap)
        cfg.line_gap = isNaN(rawGap) ? 2.5 : Math.min(50, Math.max(0, rawGap))
        const rawLine = cfg.line_enabled
        cfg.line_enabled = rawLine !== undefined && rawLine !== null &&
          !(rawLine === false || rawLine === 'false' || rawLine === 0 || rawLine === '0')
      })
    },

    applyPayload(pdfSettings = {}) {
      this.layouts = pdfSettings.custom_layouts || {}
      this.masterEnabled = pdfSettings.master_template_enabled === true || pdfSettings.master_template_enabled === 'true'
      this.masterKey = String(pdfSettings.master_template_key || '').trim()
      this.ensureLayouts()
      this.clearStaleMaster()
      // Выбранный шаблон удалён (или список пуст) — выбираем первый доступный
      const keys = Object.keys(this.layouts)
      if (!keys.includes(this.currentKey)) this.currentKey = keys[0] || ''
    },

    // --- Выбор и CRUD шаблонов ---
    select(tplKey) {
      if (!tplKey || tplKey === this.currentKey) {
        if (tplKey) this.afterSelectOverlay()
        return
      }
      this.currentKey = tplKey
      this.afterSelectOverlay()
    },
    afterSelectOverlay() {
      // В выбранном шаблоне выключен видовой экран — выключаем оверлей
      const cfg = this.layouts[this.currentKey] || {}
      if (!isSlotVisible(cfg.image_4_3, true)) {
        const settings = useSettingsStoreSafe()
        if (settings) settings.showAspectOverlay = false
        callRuby('toggleAspectOverlay', false)
      }
    },

    create(name, baseKey = 'empty', description = '') {
      const trimmedName = String(name || '').trim()
      if (!trimmedName) return
      const trimmedDesc = String(description || '').trim()
      this.ensureLayouts()
      const newKey = 'custom_' + Date.now().toString(36)
      const baseCfg = this.layouts[baseKey] ||
        { image_4_3: deepClone(DEFAULT_IMAGE_SLOT), params: [], line_gap: 2.5, line_enabled: false }
      this.layouts[newKey] = deepClone(baseCfg)
      this.layouts[newKey].name = trimmedName
      this.layouts[newKey]._name = trimmedName
      if (trimmedDesc) {
        this.layouts[newKey].description = trimmedDesc
        this.layouts[newKey]._description = trimmedDesc
      }
      this.layouts[newKey]._base_type = baseKey
      this.layouts[newKey]._icon = '📄'
      this.select(newKey)
      notifyChange()
      showToast(t('toast.templateCreated', { name: trimmedName }), 'success')
    },

    openRename(key) {
      const def = this.layouts[key] || {}
      this.modals.renameTemplate = {
        key,
        name: def._name || def.name || key,
        description: def._description || def.description || '',
      }
    },
    confirmRename(name, desc) {
      const st = this.modals.renameTemplate
      if (!st) return
      const newName = String(name || '').trim()
      if (!newName) {
        showToast(t('toast.templateNameEmpty'), 'warning')
        return
      }
      const newDesc = String(desc || '').trim()
      if (!this.layouts[st.key]) this.layouts[st.key] = {}
      this.layouts[st.key].name = newName
      this.layouts[st.key]._name = newName
      this.layouts[st.key].description = newDesc
      this.layouts[st.key]._description = newDesc
      this.modals.renameTemplate = null
      notifyChange()
      showToast(t('toast.templateRenamed', { name: newName }), 'success')
    },

    openDelete(key) {
      const def = this.layouts[key] || {}
      this.modals.deleteTemplate = { key, name: def._name || def.name || key }
    },
    confirmDelete() {
      const st = this.modals.deleteTemplate
      if (!st) return
      const tplKey = st.key
      const name = st.name
      delete this.layouts[tplKey]
      if (this.masterKey === tplKey) {
        this.masterKey = ''
        this.masterEnabled = false
      }
      // Сцены удалённого шаблона — на первый оставшийся
      const scenes = useScenesStore()
      const remaining = Object.keys(this.layouts)
      const fallbackKey = remaining[0] || ''
      let reassigned = 0
      if (fallbackKey) {
        scenes.scenes.forEach((s) => {
          if (s.page_type === tplKey) {
            s.page_type = fallbackKey
            reassigned++
          }
        })
      }
      this.modals.deleteTemplate = null
      if (fallbackKey) this.select(fallbackKey)
      else this.currentKey = ''
      notifyChange()
      showToast(
        reassigned > 0
          ? t('toast.templateDeletedScenes', { name, n: reassigned })
          : t('toast.templateDeleted', { name }),
        'info',
      )
    },

    reset() {
      const tplKey = this.currentKey
      if (!tplKey) return
      const def = this.layouts[tplKey] || {}
      const baseKey = def._base_type || (DEFAULT_LAYOUTS[tplKey] ? tplKey : 'general')
      const defTpl = DEFAULT_LAYOUTS[tplKey] || DEFAULT_LAYOUTS[baseKey] || DEFAULT_LAYOUTS.cover
      const prevMeta = {}
      ;['name', '_name', 'description', '_description', '_base_type', '_icon', '_meta'].forEach((k) => {
        if (def[k] !== undefined) prevMeta[k] = def[k]
      })
      this.layouts[tplKey] = {
        ...prevMeta,
        image_4_3: deepClone(defTpl.image_4_3 || DEFAULT_IMAGE_SLOT),
        params: [],
      }
      notifyChange()
      showToast(t('toast.templateReset', { name: this.currentDef.name }), 'success')
    },

    // --- Мастер-шаблон ---
    toggleMaster(tplKey) {
      if (!tplKey) return
      const name = (this.layouts[tplKey] && (this.layouts[tplKey]._name || this.layouts[tplKey].name)) || tplKey
      if (this.masterEnabled && this.masterKey === tplKey) {
        this.masterEnabled = false
        showToast(t('toast.masterOff', { name }), 'info')
      } else {
        this.masterKey = tplKey
        this.masterEnabled = true
        showToast(t('toast.masterOn', { name }), 'success')
      }
      notifyChange()
    },
    clearStaleMaster() {
      const keys = Object.keys(this.layouts)
      if (this.masterEnabled && !keys.includes(this.masterKey)) {
        this.masterKey = ''
        this.masterEnabled = false
      }
    },

    // --- Наборы шаблонов ---
    openSaveSet() {
      if (!Object.keys(this.layouts).length) {
        showToast(t('toast.noTemplatesToSave'), 'error')
        return
      }
      this.modals.saveSet = { name: '' }
    },
    confirmSaveSet(rawName) {
      const name = String(rawName || '').trim()
      if (!name) {
        showToast(t('toast.setNameRequired'), 'warning')
        return
      }
      this.modals.saveSet = null
      const exists = this.sets.some((s) => (s.name || '').toLowerCase() === name.toLowerCase())
      if (exists) {
        this.openConfirmSet({ type: 'overwrite', name })
      } else {
        this.doSaveSet(name)
      }
    },
    doSaveSet(name) {
      if (!Object.keys(this.layouts).length) {
        showToast(t('toast.noTemplatesToSave'), 'error')
        return
      }
      callRuby('saveTemplateSet', JSON.stringify({ name, custom_layouts: deepClone(this.layouts) }))
    },
    openConfirmSet(action) {
      const name = action ? action.name : ''
      const isDelete = !!action && action.type === 'delete'
      const isOverwrite = !!action && action.type === 'overwrite'
      const isRefresh = !!action && action.type === 'refresh'
      this.modals.confirmSet = {
        type: action ? action.type : 'load',
        name,
        title: isDelete ? t('tm.confirmDeleteTitle')
          : isOverwrite ? t('tm.confirmOverwriteTitle')
            : isRefresh ? t('tm.confirmRefreshTitle') : t('tm.confirmLoadTitle'),
        msg: isDelete ? t('tm.confirmDeleteMsg', { name })
          : isOverwrite ? t('tm.confirmOverwriteMsg', { name })
            : isRefresh ? t('tm.confirmRefreshMsg', { name }) : t('tm.confirmLoadMsg', { name }),
        danger: isDelete,
      }
    },
    confirmSetAction() {
      const action = this.modals.confirmSet
      this.modals.confirmSet = null
      if (!action) return
      if (action.type === 'delete') {
        callRuby('deleteTemplateSet', JSON.stringify(action.name))
      } else if (action.type === 'load') {
        callRuby('loadTemplateSet', JSON.stringify(action.name))
      } else if (action.type === 'overwrite' || action.type === 'refresh') {
        this.doSaveSet(action.name)
      }
    },
    onTemplateSetsUpdated(payload) {
      this.sets = (payload && payload.sets) || []
    },
    onTemplateSetLoaded(payload) {
      const layouts = payload && payload.custom_layouts
      if (!layouts || typeof layouts !== 'object') return
      this.layouts = layouts
      this.ensureLayouts()
      this.clearStaleMaster()
      // Сцены отсутствующих шаблонов → первый доступный
      const scenes = useScenesStore()
      const keys = Object.keys(layouts)
      const fallbackKey = keys[0] || ''
      if (fallbackKey) {
        scenes.scenes.forEach((s) => {
          if (!keys.includes(s.page_type)) s.page_type = fallbackKey
        })
      }
      if (!keys.includes(this.currentKey)) this.currentKey = fallbackKey
      notifyChange()
    },

    // --- Редактор параметров ---
    setParams(params, tplKey) {
      const key = tplKey || this.currentKey
      if (!this.layouts[key]) this.layouts[key] = {}
      this.layouts[key].params = (params || []).map(normalizeTemplateParam)
    },
    updateBlockSlot(blockId, updates, tplKey) {
      this.ensureLayouts()
      const key = tplKey || this.currentKey
      if (!this.layouts[key]) this.layouts[key] = {}
      if (!this.layouts[key][blockId] || typeof this.layouts[key][blockId] !== 'object') {
        this.layouts[key][blockId] = {}
      }
      Object.assign(this.layouts[key][blockId], deepClone(updates))
    },
    setVisible(id, checked) {
      const p = this.currentParams.find((x) => x.id === id)
      if (p) p.visible = checked
      notifyChange()
    },
    deleteRow(id) {
      this.setParams(this.currentParams.filter((p) => p.id !== id))
      notifyChange()
    },
    move(id, delta) {
      const params = this.currentParams
      const idx = params.findIndex((p) => p.id === id)
      const target = idx + delta
      if (idx < 0 || target < 0 || target >= params.length) return
      ;[params[idx], params[target]] = [params[target], params[idx]]
      notifyChange()
    },
    update(id, updates) {
      const p = this.currentParams.find((x) => x.id === id)
      if (p) Object.assign(p, updates)
      notifyChange()
    },
    setLineEnabled(checked) {
      const cfg = this.layouts[this.currentKey] || (this.layouts[this.currentKey] = {})
      cfg.line_enabled = checked
      notifyChange()
    },
    setLineGap(rawGap) {
      const g = parseFloat(rawGap)
      if (!isNaN(g) && g >= 0) {
        const cfg = this.layouts[this.currentKey] || (this.layouts[this.currentKey] = {})
        cfg.line_gap = g
        notifyChange()
      }
    },
    createGroup(direction) {
      const dir = direction === 'vertical' ? 'vertical' : 'horizontal'
      this.ensureLayouts()
      const cfg = this.layouts[this.currentKey] || (this.layouts[this.currentKey] = {})
      if (!Array.isArray(cfg.params)) cfg.params = []
      cfg.params.push(normalizeTemplateParam({
        group: true,
        direction: dir,
        label: '',
        show_label: false,
        align: DEFAULT_PARAM_SETTINGS.align,
        valign: DEFAULT_PARAM_SETTINGS.valign,
        font_size: DEFAULT_PARAM_SETTINGS.font_size,
        color: DEFAULT_PARAM_SETTINGS.color,
        visible: true,
        params: [],
      }))
      notifyChange()
      showToast(t(dir === 'vertical' ? 'toast.groupVCreated' : 'toast.groupHCreated'), 'success')
    },
    childOut(groupId, childId) {
      const params = this.currentParams
      const group = params.find((p) => p.id === groupId && p.group)
      if (!group || !Array.isArray(group.params)) return
      const cIdx = group.params.findIndex((c) => c.id === childId)
      if (cIdx < 0) return
      const [child] = group.params.splice(cIdx, 1)
      params.push(child)
      notifyChange()
    },
    childShowLabel(groupId, childId, checked) {
      const group = this.currentParams.find((p) => p.id === groupId && p.group)
      if (!group || !Array.isArray(group.params)) return
      const c = group.params.find((x) => x.id === childId)
      if (c) c.show_label = checked
      notifyChange()
    },
    // Drop в редакторе: op = { dragId, fromGroup, kind: 'row'|'group'|'child',
    // targetId, before, toGroup }. Порядок в списке = порядок зон на листе.
    drop(op) {
      const findGroup = (params, gid) => params.find((p) => p.id === gid && p.group)
      const params = this.currentParams
      const { dragId, fromGroup } = op

      if (op.kind === 'row') {
        if (fromGroup === null || fromGroup === undefined) {
          const fromIdx = params.findIndex((p) => p.id === dragId)
          if (fromIdx < 0) return
          const [moved] = params.splice(fromIdx, 1)
          const toIdx = params.findIndex((p) => p.id === op.targetId)
          if (toIdx < 0) params.push(moved)
          else params.splice(op.before ? toIdx : toIdx + 1, 0, moved)
        } else {
          const src = findGroup(params, fromGroup)
          const cIdx = (src && src.params ? src.params : []).findIndex((c) => c.id === dragId)
          if (cIdx < 0) return
          const [moved] = src.params.splice(cIdx, 1)
          const toIdx = params.findIndex((p) => p.id === op.targetId)
          if (toIdx < 0) params.push(moved)
          else params.splice(op.before ? toIdx : toIdx + 1, 0, moved)
        }
      } else if (op.kind === 'group') {
        let moved = null
        if (fromGroup === null || fromGroup === undefined) {
          const idx = params.findIndex((p) => p.id === dragId)
          if (idx < 0) return
          ;[moved] = params.splice(idx, 1)
        } else {
          const src = findGroup(params, fromGroup)
          const cIdx = (src && src.params ? src.params : []).findIndex((c) => c.id === dragId)
          if (cIdx < 0) return
          ;[moved] = src.params.splice(cIdx, 1)
        }
        const dst = findGroup(params, op.targetId)
        if (!dst) params.push(moved)
        else (dst.params = Array.isArray(dst.params) ? dst.params : []).push(moved)
      } else if (op.kind === 'child') {
        const src = findGroup(params, fromGroup)
        const cIdx = (src && src.params ? src.params : []).findIndex((c) => c.id === dragId)
        if (cIdx < 0) return
        const [moved] = src.params.splice(cIdx, 1)
        const dst = findGroup(params, op.toGroup)
        if (!dst) {
          const toIdx = params.findIndex((p) => p.id === op.targetId)
          if (toIdx < 0) params.push(moved)
          else params.splice(op.before ? toIdx : toIdx + 1, 0, moved)
        } else {
          const children = dst.params
          const toIdx = children.findIndex((c) => c.id === op.targetId)
          if (toIdx < 0) children.push(moved)
          else children.splice(op.before ? toIdx : toIdx + 1, 0, moved)
        }
      }
      notifyChange()
    },

    // --- Модалка параметра ---
    openNew() {
      this.ensureLayouts()
      this.modals.newTemplate = {
        name: '',
        description: '',
        base: 'empty',
        bases: [{ key: 'empty', name: t('tpl.emptyBase') }]
          .concat(this.allTemplates.map((tpl) => ({ key: tpl.key, name: tpl.name }))),
      }
    },
    confirmNewTemplate(name, baseType, description) {
      const n = String(name || '').trim()
      if (!n) {
        showToast(t('toast.templateNameRequired'), 'warning')
        return
      }
      this.create(n, baseType || 'empty', description)
      this.modals.newTemplate = null
    },

    openParamModal(mode, paramId, tplKey) {
      const key = tplKey || this.currentKey
      const existing = mode === 'edit' ? this.currentParams.find((p) => p.id === paramId) : null
      const sources = buildParamSources()
      const firstSource = sources[0] && sources[0].options[0] ? sources[0].options[0].value : ''
      this.paramModal = {
        visible: true,
        mode,
        id: paramId || null,
        tplKey: key,
        source: existing ? existing.source : firstSource,
        label: existing ? existing.label : '',
      }
    },
    closeParamModal() {
      this.paramModal.visible = false
    },
    confirmParamModal() {
      const pm = this.paramModal
      if (!pm.source) {
        showToast(t('toast.pickSource'), 'warning')
        return
      }
      const isEdit = pm.mode === 'edit'
      const existing = isEdit ? this.currentParams.find((p) => p.id === pm.id) : null
      const normalized = normalizeTemplateParam({
        id: pm.id || undefined,
        source: pm.source,
        label: String(pm.label || '').trim(),
        show_label: existing ? existing.show_label : true,
        align: existing ? existing.align : DEFAULT_PARAM_SETTINGS.align,
        valign: existing ? existing.valign : DEFAULT_PARAM_SETTINGS.valign,
        font_size: existing ? existing.font_size : DEFAULT_PARAM_SETTINGS.font_size,
        color: existing ? existing.color : DEFAULT_PARAM_SETTINGS.color,
        visible: existing ? existing.visible : true,
      })
      const key = pm.tplKey || this.currentKey
      if (!this.layouts[key]) this.layouts[key] = {}
      if (!Array.isArray(this.layouts[key].params)) this.layouts[key].params = []
      if (isEdit) {
        const idx = this.layouts[key].params.findIndex((p) => p.id === pm.id)
        if (idx >= 0) this.layouts[key].params[idx] = normalized
        else this.layouts[key].params.push(normalized)
      } else {
        this.layouts[key].params.push(normalized)
      }
      this.closeParamModal()
      notifyChange()
      showToast(t(isEdit ? 'toast.paramUpdated' : 'toast.paramCreated'), 'success')
    },
  },
})

// Настройки нужны внутри select() — лениво, чтобы не зациклить импорты
function useSettingsStoreSafe() {
  try {
    return useSettingsStore()
  } catch (e) {
    return null
  }
}
