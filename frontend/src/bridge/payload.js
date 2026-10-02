// Сборка полного payload для Ruby (saveData / startExport / saveProjectYaml /
// exportYaml). Побитовое зеркало legacy collectFormData: имена полей и формы
// данных не меняются — их разбирают белые списки ProjectData на Ruby-стороне.

import { useProjectStore } from '../stores/project.js'
import { useScenesStore } from '../stores/scenes.js'
import { useTemplatesStore } from '../stores/templates.js'
import { useDirectoriesStore } from '../stores/directories.js'
import { useSettingsStore } from '../stores/settings.js'
import { locale } from '../i18n/index.js'

export function collectFormData() {
  const project = useProjectStore()
  const scenes = useScenesStore()
  const templates = useTemplatesStore()
  const dirs = useDirectoriesStore()
  const settings = useSettingsStore()

  const room = String(project.project.place || '').trim()
  const furniture = String(project.furnitureName || '').trim()
  const computedTitle = [room, furniture].filter(Boolean).join(' — ') || 'Проект'
  const articulVal = project.articulValue
  const custVal = String(project.customer.name || '').trim()
  const compVal = String(project.customer.company || '').trim()
  const addrVal = String(project.project.adress || '').trim()
  const isCommercial = project.trade === '1'
  const tradeVal = isCommercial ? '1' : '0'
  const lastEditVal = String(project.lastEdit || '').trim()
  const materialsVal = String(project.project.materials || '').trim()
  const lightingVal = String(project.project.lighting || '').trim()
  const custIdVal = String(project.customer.id || '').trim()
  const phoneVal = String(project.customer.phone || '').trim()
  const emailVal = String(project.customer.email || '').trim()
  const authorVal = String(project.workflow.author || '').trim()
  const priceVal = String(project.workflow.price || '').trim()
  const startDateVal = String(project.workflow.start_date || '').trim()
  const endDateVal = String(project.workflow.end_date || '').trim()
  const totalDurationVal = String(project.workflow.total_duration || '').trim()
  const rateVal = String(project.workflow.rate || '').trim()

  // Статус — по последней отмеченной стадии
  const activeStadia = (project.workflow.stadia || []).filter((s) => s.status)
  const statusVal = activeStadia.length ? activeStadia[activeStadia.length - 1].name : project.workflow.status || 'Предварительный'

  const revVal = parseInt(project.workflow.revision, 10) || 1
  const verVal = parseInt(project.workflow.version, 10) || 1

  // Пары для PDF-инфолиний
  const historyEditPairs = project.history.map((item) => [item.date || '', item.text || item.description || ''])

  const productTags = furniture
    ? furniture.split(',').map((s) => s.trim()).filter(Boolean)
    : project.project.product_tags.slice()

  // Модуль 1: Project
  const outProject = {
    articul: articulVal,
    articul_locked: articulVal !== '',
    product_tags: productTags,
    product: furniture,
    place: room,
    adress: addrVal,
    materials: materialsVal,
    lighting: lightingVal,
    tags: productTags,
    commercial: isCommercial,
    name_company: compVal,
  }

  // Модуль 2: Customer
  const outCustomer = {
    id: custIdVal,
    name: custVal,
    company: compVal,
    phone: phoneVal,
    email: emailVal,
  }

  // Модуль 3: Workflow
  const outWorkflow = {
    author: authorVal,
    price: priceVal,
    start_date: startDateVal,
    end_date: endDateVal,
    total_duration: totalDurationVal,
    rate: rateVal,
    status: statusVal,
    version: String(verVal),
    revision: String(revVal),
    stadia: project.workflow.stadia || [],
    history_edit: historyEditPairs,
  }

  // Модуль 4: Корневой history_edit (project.yaml) — с версией/ревизией записи
  const historyEdit = project.history.map((item) => ({
    data: item.data || item.date || '',
    edit: item.edit || item.text || item.description || '',
    pdf_link: item.pdf_link || '',
    ver: item.ver || '',
    rev: item.rev || '',
  }))

  // Фасад project_info для 100% обратной совместимости
  const projectInfo = {
    articul: articulVal,
    articul_locked: articulVal !== '',
    name_product: furniture,
    name_place: room,
    adress: addrVal,
    customer: custVal,
    company: compVal,
    status: statusVal,
    revision: String(revVal),
    version: String(verVal),
    last_edit: lastEditVal,
    trade: tradeVal,
    tags: '',
    room_name: room,
    furniture_name: furniture,
    name_project: computedTitle,
    name_customer: custVal,
    address: addrVal,
    edit: lastEditVal,
    phone: phoneVal,
    email: emailVal,
    author: authorVal,
    price: priceVal,
    rate: rateVal,
    // Полей ТЗ в UI нет (как в legacy) — спецификации подтягиваются из папок
    task_description: '',
    task_dimensions: '',
    task_wishes: '',
    materials: materialsVal,
    appliances: '',
    lighting: lightingVal,
    notes: '',
  }

  // Синхронизация спецификаций из карточек directories (односторонняя:
  // описание папки заполняет пустое поле проекта)
  dirs.list.forEach((d) => {
    const p = (d.path || '').toLowerCase()
    const ttl = (d.title || '').toLowerCase()
    const desc = (d.description || '').trim()
    if (!desc) return
    if (p.includes('материал') || ttl.includes('материал') || p.includes('фурнитур') || ttl.includes('фурнитур')) {
      if (!String(projectInfo.materials || '').trim()) projectInfo.materials = desc
    } else if (p.includes('техник') || ttl.includes('техник') || p.includes('подсветк') || ttl.includes('подсветк')) {
      if (!projectInfo.appliances) projectInfo.appliances = desc
      if (!projectInfo.lighting) projectInfo.lighting = desc
    } else if (p.includes('замер') || ttl.includes('замер')) {
      if (!projectInfo.task_dimensions) projectInfo.task_dimensions = desc
    } else if (p.includes('инфо') || ttl.includes('инфо') || p.includes('заказчик') || ttl.includes('заказчик')) {
      if (!projectInfo.notes) projectInfo.notes = desc
    }
  })

  templates.ensureLayouts()

  const marginMm = settings.marginMm
  const outPdfSettings = {
    layout_render_mode: settings.layoutRenderMode,
    compress_pdf: settings.compressPdf === true,
    image_format: settings.imageFormat,
    webp_quality: settings.webpQuality,
    save_layout_file: settings.saveLayoutFile,
    page_size: settings.pageSize,
    page_layout: settings.pageLayout,
    margin_mm: parseFloat(marginMm) || 0,
    margin: Math.round(((parseFloat(marginMm) || 0) * 72.0) / 25.4 * 10) / 10,
    image_aspect_ratio: settings.imageAspectRatio,
    custom_ratio_w: parseFloat(settings.customRatioW) || 16,
    custom_ratio_h: parseFloat(settings.customRatioH) || 9,
    show_aspect_overlay: Boolean(settings.showAspectOverlay),
    overlay_border_color: settings.overlayBorderColor,
    overlay_border_opacity: settings.overlayBorderOpacity,
    overlay_mask_color: settings.overlayMaskColor,
    overlay_mask_opacity: settings.overlayMaskOpacity,
    render_quality: settings.renderQuality,
    image_width: settings.effectiveRenderWidth,
    scale_multiplier: settings.scaleMultiplier,
    scale_factor: settings.effectiveScaleMultiplier,
    annotation_font_size: settings.annotationFontSize,
    font_family: settings.fontFamily,
    // Начертание/ширина выведены из GUI: шлём дефолты, чтобы старые
    // сохранённые значения сходились к ним при следующем сохранении
    font_weight: 'normal',
    font_width: 'condensed',
    primary_color: String(settings.primaryColor || '').replace('#', ''),
    auto_open_pdf: settings.autoOpenPdf,
    save_skp_backup: settings.saveSkpBackup,
    antialias: settings.antialias,
    // Язык интерфейса: источник истины — реактивная локаль i18n
    language: locale.value === 'en' ? 'en' : 'ru',
    // Мастер-шаблон (основа всех страниц, кроме обложек)
    master_template_enabled: templates.masterEnabled,
    master_template_key: templates.masterKey,
    custom_layouts: templates.layouts,
  }

  const apiTargets = settings.apiTargets.map((x) => String(x).trim()).filter(Boolean)

  const cleanDirs = dirs.list.map(({ path, title, description, send_to_server, thumb_size }) => ({
    path, title, description, send_to_server, thumb_size,
  }))

  return {
    project: outProject,
    customer: outCustomer,
    workflow: outWorkflow,
    project_info: projectInfo,
    history_edit: historyEdit,
    history: project.history,
    directories: cleanDirs,
    scenes: scenes.scenes,
    pdf_settings: outPdfSettings,
    api_targets: apiTargets,
    template_sets: templates.sets,
  }
}
