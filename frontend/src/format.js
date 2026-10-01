// Общие утилиты форматирования
import { locale, t } from './i18n/index.js'
import {
  FileText, Image as ImageIcon, Ruler, Table2, File as FileIcon,
} from '@lucide/vue'

export function formatFileSize(bytes) {
  if (!bytes || bytes <= 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i]
}

// Иконка файла по расширению (компонент lucide)
export function docIcon(ext) {
  const e = String(ext || '').toUpperCase()
  if (e === 'PDF') return FileText
  if (e === 'DWG' || e === 'DXF' || e === 'SKP') return Ruler
  if (e === 'DOC' || e === 'DOCX' || e === 'TXT' || e === 'RTF') return FileText
  if (e === 'XLS' || e === 'XLSX' || e === 'CSV') return Table2
  if (isImageExt(e)) return ImageIcon
  return FileIcon
}

export function isImageExt(ext) {
  return ['JPG', 'JPEG', 'PNG', 'WEBP', 'GIF', 'BMP', 'TIF', 'TIFF'].includes(String(ext || '').toUpperCase())
}

// Плюрализация для счётчика файлов
export function pluralFiles(n) {
  if (locale.value === 'en') {
    return n === 1 ? t('plural.fileOne') : t('plural.fileMany')
  }
  if (n === 1) return t('plural.fileOne')
  if (n >= 2 && n <= 4) return t('plural.fileFew')
  return t('plural.fileMany')
}
