// Данные проекта: паспорт, заказчик, ход работы (включая стадии и историю
// правок). Артикул создаётся один раз и дальше не меняется; тип проекта
// (коммерческий/бытовой) выводится из поля commercial и префикса артикула.

import { defineStore } from 'pinia'
import { callRuby } from '../bridge/sketchup.js'
import { notifyChange } from './autosave.js'
import { t } from '../i18n/index.js'
import { nowStamp } from '../lib/dates.js'
import { formatCost, parseDurationHours, parseRate } from '../lib/calc.js'

const tval = (v) => String(v === undefined || v === null ? '' : v).trim()

// Стадии по умолчанию (если в проекте пусто) — как в legacy renderStadia
export const DEFAULT_STADIA = [
  { name: 'Предварительный проект', status: true },
  { name: 'Правки проекта (история правок)', status: false },
  { name: 'Выбраны материалы и фурнитура', status: false },
  { name: 'Предварительно Утвержден', status: false },
  { name: 'Проверка технологом', status: false },
  { name: 'Утвержден', status: false },
  { name: 'Отправлен в производство', status: false },
  { name: 'Оплачен', status: false },
]

// Суффикс ревизии, вшитый в текст старых записей истории: "(rev. 004)"
const HISTORY_REV_SUFFIX_RE = /\s*\(rev\.?\s*(\d{1,})\)\s*$/i

function splitRevSuffix(text) {
  const raw = String(text || '')
  const m = raw.match(HISTORY_REV_SUFFIX_RE)
  if (!m) return { text: raw.trim(), rev: '' }
  return { text: raw.replace(HISTORY_REV_SUFFIX_RE, '').trim(), rev: m[1].padStart(3, '0') }
}

// Чистый текст + отдельные поля ver/rev; ревизию из текста переносим в поле
export function migrateHistoryEntries(history) {
  ;(history || []).forEach((item) => {
    if (!item || typeof item !== 'object') return
    item.ver = String(item.ver || '').trim()
    item.rev = String(item.rev || '').trim()
    item.skp_link = String(item.skp_link || '').trim()
    const clean = splitRevSuffix(item.text || item.edit || item.description || '')
    if (!item.rev && clean.rev) item.rev = clean.rev
    if (clean.rev) {
      item.text = clean.text
      item.edit = clean.text
      item.description = clean.text
    }
  })
  return history
}

export function generateArticulLocal(isCommercial) {
  const prefix = isCommercial ? 'CF#' : 'HF#'
  const now = new Date()
  const p = (n) => String(n).padStart(2, '0')
  return `${prefix}${String(now.getFullYear()).slice(-2)}${p(now.getMonth() + 1)}${p(now.getDate())}_${p(now.getHours())}${p(now.getMinutes())}${p(now.getSeconds())}`
}

export const useProjectStore = defineStore('project', {
  state: () => ({
    project: {
      articul: '',
      articul_locked: false,
      product_tags: [],
      product: '',
      place: '',
      adress: '',
      materials: '',
      lighting: '',
      tags: [],
      commercial: false,
      name_company: '',
    },
    customer: { id: '', name: '', company: '', phone: '', email: '' },
    workflow: {
      author: '',
      price: '',
      start_date: '',
      end_date: '',
      total_duration: '',
      rate: '',
      version: '1',
      revision: '1',
      stadia: [],
      history_edit: [],
    },
    // Поле «Последняя правка» (в legacy — отдельный input, в collect —
    // project_info.last_edit)
    lastEdit: '',
    // Скрытые поля ТЗ/спецификаций (заполняются синком папок, UI-полей нет —
    // как в legacy)
    taskDescription: '',
    taskDimensions: '',
    taskWishes: '',
    appliances: '',
    notes: '',
    // История правок: { data, date, edit, text, description, pdf_link, ver, rev }
    history: [],
    // '1' — коммерческий, '0' — бытовой
    trade: '0',
  }),

  getters: {
    articulValue(state) {
      return String(state.project.articul || '').trim()
    },
    isCommercial(state) {
      return state.trade === '1'
    },
    // Отображаемое имя изделия: строка «Изделие», при пустой — теги через запятую.
    // product первичен: иначе правка поля не попадает в payload (теги старше)
    furnitureName(state) {
      const product = String(state.project.product || '').trim()
      if (product) return product
      const tags = state.project.product_tags
      return Array.isArray(tags) && tags.length ? tags.join(', ') : ''
    },
    // Шапка, строка 1: название изделия
    headerProduct(state) {
      const name = String(this.furnitureName || '').trim()
      return { text: name || t('app.newProject'), real: Boolean(name) }
    },
    // Шапка, строка 2: помещение — адрес
    headerPlaceAdress(state) {
      const parts = [String(state.project.place || '').trim(), String(state.project.adress || '').trim()].filter(Boolean)
      return { text: parts.join(' — ') || t('app.headerPlacePlaceholder'), real: parts.length > 0 }
    },
    // Шапка, строка 3: заказчик, у коммерческих — компания (если заполнена)
    headerClient(state) {
      const name = String(state.customer.name || '').trim()
      const company = String(state.customer.company || '').trim()
      const text = this.isCommercial ? (company || name) : (name || company)
      return { text: text || t('app.headerClientPlaceholder'), real: Boolean(text) }
    },
    versionNum(state) {
      return parseInt(state.workflow.version, 10) || 1
    },
    revisionNum(state) {
      return parseInt(state.workflow.revision, 10) || 1
    },
  },

  actions: {
    applyPayload(data = {}) {
      const prj = data.project || {}
      const cust = data.customer || {}
      const wf = data.workflow || {}
      const info = data.project_info || {}

      // История: state.history — основной источник, пары workflow.history_edit —
      // только fallback (приходят из Ruby с pdf_link/ver/rev)
      let history = data.history
      if (!Array.isArray(history) || history.length === 0) {
        if (Array.isArray(wf.history_edit) && wf.history_edit.length > 0) {
          history = wf.history_edit.map((item) => {
            if (Array.isArray(item)) {
              return { date: item[0] || '', text: item[1] || '', description: item[1] || '', pdf_link: item[2] || '', skp_link: item[3] || '', ver: '', rev: '' }
            }
            if (item && typeof item === 'object') {
              const txt = item.text || item.description || ''
              return {
                date: item.date || '',
                text: txt,
                description: txt,
                pdf_link: item.pdf_link || '',
                skp_link: item.skp_link || '',
                ver: item.ver || item.version || '',
                rev: item.rev || item.revision || '',
              }
            }
            return { date: '', text: String(item || ''), description: String(item || ''), ver: '', rev: '' }
          })
        } else {
          history = []
        }
      }
      this.history = history
      migrateHistoryEntries(this.history)
      if (this.history.length > 0) {
        this.workflow.history_edit = this.history.map((item) => [item.date || '', item.text || item.description || ''])
      }

      // Паспорт
      this.project.articul = tval(prj.articul) || tval(info.articul)
      this.project.articul_locked = this.articulValue !== ''
      const pTags = prj.product_tags || info.product_tags
      this.project.product_tags = Array.isArray(pTags) ? pTags.slice() : []
      this.project.product = tval(prj.product) || tval(info.name_product) || tval(info.furniture_name) || tval(prj.tags) || tval(info.tags)
      const tagsVal = prj.tags !== undefined ? prj.tags : info.tags
      this.project.tags = Array.isArray(tagsVal) ? tagsVal.slice() : []
      this.project.place = tval(prj.place) || tval(info.name_place) || tval(info.room_name)
      this.project.adress = tval(prj.adress) || tval(info.adress) || tval(info.address)
      this.project.materials = tval(prj.materials) || tval(info.materials)
      this.project.lighting = tval(prj.lighting) || tval(info.lighting)
      this.project.name_company = tval(cust.company) || tval(prj.name_company) || tval(info.company)

      // Тип проекта
      const isCommercial =
        prj.commercial !== undefined
          ? Boolean(prj.commercial)
          : info.trade === 1 || info.trade === '1' || this.articulValue.startsWith('CF#')
      this.setTrade(isCommercial ? '1' : '0')

      // Заказчик
      this.customer.id = tval(cust.id) || tval(cust.customer_id)
      this.customer.name = tval(cust.name) || tval(info.customer) || tval(info.name_customer)
      this.customer.company = tval(cust.company) || tval(prj.name_company) || tval(info.company)
      this.customer.phone = tval(cust.phone) || tval(info.phone)
      this.customer.email = tval(cust.email) || tval(info.email)

      // Ход работы
      this.workflow.author = tval(wf.author) || tval(info.author)
      this.workflow.price = wf.price !== undefined && wf.price !== null ? String(wf.price) : tval(info.price)
      this.workflow.start_date = tval(wf.start_date)
      this.workflow.end_date = tval(wf.end_date)
      this.workflow.total_duration = tval(wf.total_duration)
      this.workflow.rate = tval(wf.rate) || tval(info.rate)
      this.workflow.version = String(parseInt(wf.version ?? info.version, 10) || 1)
      this.workflow.revision = String(parseInt(wf.revision ?? info.revision, 10) || 1)
      this.lastEdit = tval(info.last_edit) || tval(info.edit)

      // Стоимость: при загрузке только заполняем пустое поле (ручное значение
      // не трогаем)
      this.recalcPrice(false)

      // Стадии
      let stadia = this.workflow.stadia || wf.stadia
      if (!Array.isArray(stadia) || stadia.length === 0) stadia = DEFAULT_STADIA.map((s) => ({ ...s }))
      this.workflow.stadia = stadia.map((s) => ({
        name: tval(s && s.name),
        status: !!(Array.isArray(s) ? s[1] : s && s.status),
      }))

      // Скрытые поля ТЗ/спецификаций
      this.taskDescription = tval(info.task_description) || tval(prj.description)
      this.taskDimensions = tval(info.task_dimensions)
      this.taskWishes = tval(info.task_wishes)
      this.appliances = tval(info.appliances)
      this.notes = tval(info.notes)
    },

    setTrade(val) {
      this.trade = String(val) === '1' ? '1' : '0'
      this.project.commercial = this.trade === '1'
    },

    setArticul(val) {
      this.project.articul = String(val || '').trim()
      this.project.articul_locked = this.articulValue !== ''
      if (this.articulValue.startsWith('CF#')) this.setTrade('1')
      else if (this.articulValue.startsWith('HF#')) this.setTrade('0')
    },

    // product_tags — зеркало строки «Изделие» (в Ruby то же делает прокси
    // project_info на ключе :product): синхрон на вводе, чтобы payload
    // и шапка не возвращали старые теги после правки поля
    syncProductTags(val) {
      this.project.product_tags = String(val || '').split(',').map((s) => s.trim()).filter(Boolean)
    },

    // Автостоимость: Ставка (₽/ч) × Время. force=true — перезаписать любое
    // значение (реакция на правку Ставки/Времени в форме); false — заполнить
    // только пустое поле (загрузка проекта, подтяжка времени из статистики).
    // Возвращает true, если стоимость изменилась.
    recalcPrice(force = true) {
      const rate = parseRate(this.workflow.rate)
      const hours = parseDurationHours(this.workflow.total_duration)
      if (!(rate > 0) || !(hours > 0)) return false
      const cost = formatCost(rate * hours)
      const current = String(this.workflow.price || '').trim()
      if ((!force && current !== '') || current === cost) return false
      this.workflow.price = cost
      return true
    },

    stadiaChanged() {
      notifyChange()
    },
    addStadia(name) {
      const n = String(name || '').trim()
      if (!n) return
      this.workflow.stadia.push({ name: n, status: false })
      notifyChange()
    },
    removeStadia(index) {
      if (this.workflow.stadia.length <= 1) return
      this.workflow.stadia.splice(index, 1)
      notifyChange()
    },
    renameStadia(index, name) {
      const n = String(name || '').trim()
      const item = this.workflow.stadia[index]
      if (!item || !n || item.name === n) return
      item.name = n
      notifyChange()
    },
    moveStadia(from, to) {
      const arr = this.workflow.stadia
      const [item] = arr.splice(from, 1)
      arr.splice(to, 0, item)
      notifyChange()
    },
    // Сохранить имена стадий как глобальный список по умолчанию (settings.yaml)
    saveStadiaDefault() {
      const names = this.workflow.stadia.map((s) => (s && s.name ? String(s.name) : '')).filter((n) => n.trim().length > 0)
      if (!names.length) return
      callRuby('saveStadiaDefault', JSON.stringify({ stadia: names }))
    },

    // --- История правок ---
    addHistoryEntry() {
      const defaultText = t('hist.defaultEntry')
      const stamp = nowStamp()
      this.history.unshift({
        data: stamp,
        date: stamp,
        edit: defaultText,
        text: defaultText,
        description: defaultText,
        pdf_link: '',
        skp_link: '',
        ver: '',
        rev: '',
      })
      this.lastEdit = defaultText
      this.syncHistoryEditPairs()
      notifyChange()
    },
    removeHistoryEntry(index) {
      this.history.splice(index, 1)
      this.syncHistoryEditPairs()
      notifyChange()
    },
    // Ввод текста правки: три поля записи + «Последняя правка» для первой строки
    syncHistoryEdit(index, value) {
      const item = this.history[index]
      if (!item) return
      item.edit = value
      item.text = value
      item.description = value
      if (index === 0) this.lastEdit = value
      this.syncHistoryEditPairs()
    },
    syncHistoryEditPairs() {
      this.workflow.history_edit = this.history.map((item) => [item.date || '', item.text || item.description || ''])
    },
    // Штамп PDF экспорта к самой свежей записи (зеркало Ruby stamp_history_pdf_link!)
    stampHistoryPdfLink(pdfPath) {
      const first = this.history[0]
      if (first && !String(first.pdf_link || '').trim()) {
        first.pdf_link = pdfPath
        this.syncHistoryEditPairs()
        notifyChange()
      }
    },
    // Штамп SKP-копии экспорта к самой свежей записи (зеркало Ruby stamp_history_skp_link!)
    stampHistorySkpLink(skpPath) {
      const first = this.history[0]
      if (first && skpPath && !String(first.skp_link || '').trim()) {
        first.skp_link = skpPath
        this.syncHistoryEditPairs()
        notifyChange()
      }
    },
  },
})
