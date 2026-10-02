// Авто-расчёт стоимости: Ставка (₽/ч) × Время.
// «Время» — свободная строка: «45 мин», «2 ч 30 мин», «1 д 4 ч»,
// «14 дней / 65 часов», «12h 40m» или просто число (трактуется как часы).
// Формат «дни / часы» через «/» — две записи одной длительности: берём часть
// с часами (если есть), иначе последнюю. Составные «1 д 4 ч» суммируются.

// Число из строки ставки: «1500», «1 500 руб/ч», «1000,5» → 1500 / 1500 / 1000.5
export function parseRate(raw) {
  const s = String(raw || '').replace(/\s+/g, '')
  const m = s.match(/\d+(?:[.,]\d+)?/)
  if (!m) return 0
  const n = parseFloat(m[0].replace(',', '.'))
  return Number.isFinite(n) ? n : 0
}

// Разбор одного фрагмента длительности (без «/»): сумма чисел по единицам.
// bare — первое число без единицы; строка только из числа = часы.
function partHours(part) {
  const tokenRe = /(\d+(?:[.,]\d+)?)\s*(дн[а-яё]*|день|д(?![а-яё])|days?|d(?![a-zа-яё])|час[а-яё]*|ч(?![а-яё])|hours?|h(?![a-zа-яё])|мин[а-яё]*|м(?![а-яё])|minutes?|min(?![a-zа-яё])|m(?![a-zа-яё]))?/g
  let hours = 0
  let sawUnit = false
  let sawHours = false
  let bare = null
  for (const m of part.matchAll(tokenRe)) {
    const n = parseFloat(m[1].replace(',', '.'))
    if (!Number.isFinite(n)) continue
    const unit = m[2] || ''
    if (!unit) {
      if (bare === null) bare = n
      continue
    }
    sawUnit = true
    if (/^(дн|д|d)/.test(unit)) hours += n * 24
    else if (/^(час|ч|h)/.test(unit)) {
      hours += n
      sawHours = true
    } else if (/^(мин|м|m)/.test(unit)) hours += n / 60
    else hours += n
  }
  if (sawUnit) return { hours, sawHours }
  return { hours: bare || 0, sawHours: true }
}

// Часы из строки длительности; 0 — если распознать не удалось
export function parseDurationHours(raw) {
  const s = String(raw || '').toLowerCase()
  if (!s.trim()) return 0
  if (!s.includes('/')) return partHours(s).hours
  const parts = s
    .split('/')
    .map(partHours)
    .filter((p) => p.hours > 0)
  if (parts.length === 0) return 0
  const hoursPart = parts.find((p) => p.sawHours)
  return (hoursPart || parts[parts.length - 1]).hours
}

// Стоимость строкой: целые с пробельными группами «97 500», дробные «2 501,25»
export function formatCost(value) {
  if (!Number.isFinite(value) || value <= 0) return ''
  const [int, frac] = value.toFixed(2).split('.')
  const grouped = int.replace(/\B(?=(\d{3})+(?!\d))/g, ' ')
  const fracTrim = frac.replace(/0+$/, '')
  return fracTrim ? `${grouped},${fracTrim}` : grouped
}
