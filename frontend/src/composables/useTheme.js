// Тема диалога (светлая/тёмная), паттерн соседних расширений
// (dn1sup_create_project / dn1sup_time_project useTheme.js).
// Отличия: свой ключ localStorage, чтобы не пересекаться с соседями.

import { ref } from 'vue'

const STORAGE_KEY = 'dn1sup_export_pdf2_theme'

const isDark = ref(false)

function applyTheme(dark) {
  isDark.value = Boolean(dark)
  if (typeof document !== 'undefined' && document.documentElement) {
    document.documentElement.classList.toggle('dark', isDark.value)
  }
  try {
    localStorage.setItem(STORAGE_KEY, isDark.value ? 'dark' : 'light')
  } catch {
    // CEF может запрещать localStorage — тема просто не переживёт перезапуск
  }
}

function toggleTheme() {
  applyTheme(!isDark.value)
}

// Синхронное чтение для старта без мерцания (вызывается из main.js до mount)
function initTheme() {
  let dark = false
  try {
    dark = localStorage.getItem(STORAGE_KEY) === 'dark'
  } catch {
    dark = false
  }
  applyTheme(dark)
}

export function useTheme() {
  return { isDark, toggleTheme, applyTheme, initTheme }
}
