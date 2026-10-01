// Лёгкий i18n без внешних зависимостей: реактивная локаль (Vue ref) + t(key).
// Используется и Vue-компонентами (реактивная перерисовка при смене локали),
// и legacy/app.js (runtime-строки и статический ре-рендер). Источник истины —
// pdf_settings.language из settings.yaml (Ruby); localStorage — только кэш
// для мгновенного старта без мерцания до прихода payload getData.
import { ref } from 'vue'
import { ru } from './ru.js'
import { en } from './en.js'

const DICTS = { ru, en }

export const LOCALES = [
  { value: 'ru', label: 'Русский' },
  { value: 'en', label: 'English' },
]

const STORAGE_KEY = 'dn1c_lang'

function normalizeLang(v) {
  return String(v || '').toLowerCase().trim() === 'en' ? 'en' : 'ru'
}

function cachedLang() {
  try {
    return normalizeLang(localStorage.getItem(STORAGE_KEY))
  } catch (e) {
    return 'ru'
  }
}

export const locale = ref(cachedLang())

// Перевод по ключу с интерполяцией {param}; фолбэк: текущая локаль → ru → ключ
export function t(key, params) {
  const dicts = [DICTS[locale.value], ru]
  for (const d of dicts) {
    const s = d && d[key]
    if (typeof s === 'string') {
      if (!params) return s
      return s.replace(/\{(\w+)\}/g, (m, name) =>
        params[name] !== undefined && params[name] !== null ? String(params[name]) : m)
    }
  }
  return key
}

export function currentLocale() {
  return locale.value
}

export function setLocale(lang) {
  const next = normalizeLang(lang)
  if (locale.value !== next) {
    locale.value = next
    try { localStorage.setItem(STORAGE_KEY, next) } catch (e) { /* CEF может запрещать */ }
  }
  if (typeof document !== 'undefined' && document.documentElement) {
    document.documentElement.lang = next
  }
}
