// Красные волнистые подчёркивания опечаток: плавающий оверлей поверх поля.
// Текст в оверлее прозрачный — видна только декорация подчёркивания, поэтому
// вёрстка полей не меняется, а шрифт и отступы зеркалируются из computed style.
import { checkText, ensureDicts, isReady } from './engine.js'

const states = new WeakMap() // поле -> { el, ov, ranges, timer, visible, handlers }
const tracked = new Set() // поля с видимой подсветкой (для scroll/resize)
const DEBOUNCE_MS = 250

function escapeHtml(s) {
  return s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]))
}

function buildHtml(value, ranges) {
  let html = ''
  let pos = 0
  for (const r of ranges) {
    html += escapeHtml(value.slice(pos, r.start))
    html += '<span class="dn1-spell-err">' + escapeHtml(value.slice(r.start, r.end)) + '</span>'
    pos = r.end
  }
  return html + escapeHtml(value.slice(pos))
}

function positionOverlay(st) {
  const { el, ov } = st
  const cs = getComputedStyle(el)
  const rect = el.getBoundingClientRect()
  ov.style.left = rect.left + (parseFloat(cs.borderLeftWidth) || 0) + 'px'
  ov.style.top = rect.top + (parseFloat(cs.borderTopWidth) || 0) + 'px'
  ov.style.width = el.clientWidth + 'px'
  ov.style.height = el.clientHeight + 'px'
  ov.style.fontFamily = cs.fontFamily
  ov.style.fontSize = cs.fontSize
  ov.style.fontWeight = cs.fontWeight
  ov.style.fontStyle = cs.fontStyle
  ov.style.letterSpacing = cs.letterSpacing
  ov.style.lineHeight = cs.lineHeight
  ov.style.textAlign = cs.textAlign
  ov.style.textTransform = cs.textTransform
  ov.style.paddingLeft = cs.paddingLeft
  ov.style.paddingRight = cs.paddingRight
  ov.style.paddingTop = cs.paddingTop
  ov.style.paddingBottom = cs.paddingBottom
  ov.style.whiteSpace = el.tagName === 'TEXTAREA' ? 'pre-wrap' : 'pre'
}

function hide(st) {
  st.ov.style.display = 'none'
  st.visible = false
  tracked.delete(st.el)
}

function render(st) {
  const { el, ov } = st
  const value = el.value
  if (!value || !isReady()) {
    hide(st)
    return
  }
  st.ranges = checkText(value)
  if (!st.ranges.length) {
    hide(st)
    return
  }
  positionOverlay(st)
  ov.innerHTML = buildHtml(value, st.ranges)
  ov.style.display = 'block'
  ov.scrollLeft = el.scrollLeft
  ov.scrollTop = el.scrollTop
  st.visible = true
  tracked.add(el)
}

function schedule(st) {
  clearTimeout(st.timer)
  st.timer = setTimeout(() => {
    ensureDicts()
    render(st)
  }, DEBOUNCE_MS)
}

function onContextMenu(e, st) {
  if (!isReady() || !st.ranges.length) return
  const pos = st.el.selectionStart ?? st.el.value.length
  const hit = st.ranges.find((r) => pos >= r.start && pos <= r.end)
  if (!hit) return
  e.preventDefault()
  window.dispatchEvent(new CustomEvent('dn1-spell-menu', {
    detail: { x: e.clientX, y: e.clientY, el: st.el, range: hit },
  }))
}

export function attachField(el) {
  if (states.has(el)) return
  const ov = document.createElement('div')
  ov.className = 'dn1-spell-overlay'
  document.body.appendChild(ov)
  const st = { el, ov, ranges: [], timer: 0, visible: false, handlers: {} }
  states.set(el, st)
  st.handlers = {
    focus: () => { ensureDicts(); render(st) },
    input: () => schedule(st),
    blur: () => setTimeout(() => { if (!el.matches(':focus')) hide(st) }, 120),
    scroll: () => {
      if (st.visible) {
        st.ov.scrollLeft = el.scrollLeft
        st.ov.scrollTop = el.scrollTop
      }
    },
    contextmenu: (e) => onContextMenu(e, st),
  }
  for (const [name, fn] of Object.entries(st.handlers)) el.addEventListener(name, fn)
}

export function detachField(el) {
  const st = states.get(el)
  if (!st) return
  clearTimeout(st.timer)
  for (const [name, fn] of Object.entries(st.handlers)) el.removeEventListener(name, fn)
  st.ov.remove()
  tracked.delete(el)
  states.delete(el)
}

export function refreshField(el) {
  const st = states.get(el)
  if (st && (st.visible || el.matches(':focus'))) render(st)
}

// Замена слова выбранным вариантом: через событие input, чтобы обновился v-model
export function applySuggestion(el, range, replacement) {
  el.value = el.value.slice(0, range.start) + replacement + el.value.slice(range.end)
  el.dispatchEvent(new Event('input', { bubbles: true }))
  const caret = range.start + replacement.length
  el.focus()
  try { el.setSelectionRange(caret, caret) }
  catch { /* типы полей без каретки */ }
  refreshField(el)
}

// Оверлеи плавают в координатах окна — следим за прокруткой и ресайзом
window.addEventListener('scroll', () => {
  for (const el of tracked) positionOverlay(states.get(el))
}, true)
window.addEventListener('resize', () => {
  for (const el of tracked) positionOverlay(states.get(el))
})

// v-spell на <input>/<textarea>: false отключает проверку для поля
export const vSpell = {
  mounted(el, binding) {
    if (binding.value !== false) attachField(el)
  },
  unmounted(el) {
    detachField(el)
  },
}
