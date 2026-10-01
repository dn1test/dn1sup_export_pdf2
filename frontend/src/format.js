// Общие утилиты форматирования, используются и legacy-кодом, и Vue-компонентами.
import { locale, t } from './i18n/index.js'

export function formatFileSize(bytes) {
  if (!bytes || bytes <= 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i]
}

export function getDocIcon(ext) {
  ext = (ext || '').toUpperCase()
  if (ext === 'PDF') return '<i class="modus-icons">file_template</i>'
  if (ext === 'DWG' || ext === 'DXF') return '<i class="modus-icons">views</i>'
  if (ext === 'SKP') return '<i class="modus-icons">views</i>'
  if (ext === 'DOC' || ext === 'DOCX' || ext === 'TXT' || ext === 'RTF') return '<i class="modus-icons">short_text</i>'
  if (ext === 'XLS' || ext === 'XLSX' || ext === 'CSV') return '<i class="modus-icons">table</i>'
  return '<i class="modus-icons">file</i>'
}

// Плюрализация для счётчика файлов: русская (1 файл / 2-4 файла / 5 файлов)
// и английская (1 file / N files) ветки
export function pluralFiles(n) {
  if (locale.value === 'en') {
    return n === 1 ? t('plural.fileOne') : t('plural.fileMany')
  }
  if (n === 1) return t('plural.fileOne')
  if (n >= 2 && n <= 4) return t('plural.fileFew')
  return t('plural.fileMany')
}

// Крестик удаления в стиле Modus (иконка из шрифта)
export const MODUS_CROSS_SVG =
  '<i class="modus-icons icon-close-cross" style="font-size: 11px;">content_close</i>'
