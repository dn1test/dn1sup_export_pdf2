// Краткая справка для кружка «!» у параметра шаблона: что за данные и как
// параметр ведёт себя на листе. Семантика источников — зеркало
// InfoLineResolver.resolve_param (service/info_line_resolver.rb);
// ключи совпадают с buildParamSources (legacy/app.js) — держать синхронно.
// Тексты справки живут в словарях i18n (ключи «help.*»).

import { t } from '../i18n/index.js'

// Источники, значение которых пользователь заполняет сам: пустое поле не печатается
const FILLED_BY_USER = new Set([
  "project.articul", "project.address", "project.materials", "project.lighting",
  "customer.id", "customer.name", "customer.phone", "customer.email",
  "workflow.author", "workflow.rate",
])

export function paramHelpTitle(p) {
  if (!p) return ""
  if (p.group) {
    return t(p.direction === "vertical" ? "help.group.vertical" : "help.group.horizontal")
  }
  const s = String(p.source || "")
  const dir = s.match(/^dir\.(\d+)\.(title|description|line)$/)
  if (dir) return t(`help.dir.${dir[2]}`)
  const text = t(`help.${s}`)
  // Нет перевода — t возвращает сам ключ: показываем стандартную подсказку
  if (text === `help.${s}`) return t("help.default")
  return FILLED_BY_USER.has(s) ? text + t("help.userFillNote") : text
}
