// Работа с датами проекта. Пользователь видит и вводит «дд.мм.гггг», хранение —
// ISO (YYYY-MM-DD), как в сохранённых project.yaml. Нативный <input type="date">
// в CEF всегда рисует американский порядок, поэтому календарь спрятан за иконкой.

const pad2 = (n) => String(n).padStart(2, '0')

export const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}$/

export function isoToRuDate(v) {
  const m = String(v || '').trim().match(/^(\d{4})-(\d{2})-(\d{2})$/)
  return m ? `${m[3]}.${m[2]}.${m[1]}` : String(v || '')
}

// «д.м.гггг» (точки/слэши/дефисы) → ISO или null
export function parseRuDate(s) {
  const m = String(s || '').trim().match(/^(\d{1,2})[.\/-](\d{1,2})[.\/-](\d{4})$/)
  if (!m) return null
  const d = Number(m[1])
  const mo = Number(m[2])
  const y = Number(m[3])
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null
  const dt = new Date(y, mo - 1, d)
  return dt.getFullYear() === y && dt.getMonth() === mo - 1 && dt.getDate() === d
    ? `${y}-${pad2(mo)}-${pad2(d)}`
    : null
}

// Дата в печатном формате PDF (dd.mm.yyyy), а не в локали браузера
export function previewDate(d) {
  const s = String(d || '').trim()
  if (s) return s
  const now = new Date()
  return `${pad2(now.getDate())}.${pad2(now.getMonth() + 1)}.${now.getFullYear()}`
}

// «2026-09-24 10:30» — штамп момента для истории ревизий
export function nowStamp() {
  const now = new Date()
  return `${now.getFullYear()}-${pad2(now.getMonth() + 1)}-${pad2(now.getDate())} ` +
    `${pad2(now.getHours())}:${pad2(now.getMinutes())}`
}

export function nowStampSec() {
  const now = new Date()
  return `${now.getFullYear()}-${pad2(now.getMonth() + 1)}-${pad2(now.getDate())} ` +
    `${pad2(now.getHours())}:${pad2(now.getMinutes())}:${pad2(now.getSeconds())}`
}
