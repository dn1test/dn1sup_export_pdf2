// Dev-мок: ответы Ruby-колбэков при просмотре GUI в браузере (npm run dev,
// localhost:5173). В живом SketchUp не используется — callRuby уходит в мост.
// payload getData держит те же ключи, что и Ruby (test_frontend_consistency.rb
// сверяет их с default_pdf_settings).

function delay(fn, ms = 50) {
  setTimeout(fn, ms)
}

const pad = (n) => String(n).padStart(2, '0')

function buildGetDataPayload() {
  const scenesList = [
    { name: 'Титульный лист', page_type: 'cover', description: 'Обложка проекта', enabled: true, aspect_ratio: '4:3', scale_pct: 100, viewport_visible: true, align_h: 'center', align_v: 'center' },
    { name: 'Содержание и материалы', page_type: 'explain', description: 'Пояснительная записка и перечень спецификаций', enabled: true, aspect_ratio: '4:3', scale_pct: 90, viewport_visible: true, align_h: 'center', align_v: 'center' },
    { name: 'Перспективный вид', page_type: 'visual', description: 'Визуализация интерьера в дневном освещении', enabled: true, aspect_ratio: '16:9', scale_pct: 100, viewport_visible: true, align_h: 'center', align_v: 'center' },
    { name: 'План расстановки мебели', page_type: 'general', description: 'Техническая схема с габаритными размерами', enabled: true, aspect_ratio: '4:3', scale_pct: 80, viewport_visible: true, align_h: 'center', align_v: 'center' },
  ]
  const stadia = [
    { name: 'Предварительный проект', status: true },
    { name: 'Правки проекта (история правок)', status: true },
    { name: 'Выбраны материалы и фурнитура', status: true },
    { name: 'Предварительно Утвержден', status: true },
    { name: 'Проверка технологом', status: false },
    { name: 'Утвержден в производство', status: false },
  ]
  const history = [
    { data: '2026-09-24 10:30', edit: 'Корректировка фасадов шкафа (rev. 003)', pdf_link: 'project_rev003.pdf', ver: '02', rev: '003' },
    { data: '2026-09-20 15:45', edit: 'Первоначальное согласование', pdf_link: '', ver: '02', rev: '002' },
    { data: '2026-09-15 11:20', edit: 'Создание проекта', pdf_link: '', ver: '01', rev: '001' },
  ]
  const param = (source, label, align, valign, fs, color) => ({
    id: 'p_' + source.replace(/\W/g, '_'), source, label: label || '', show_label: !label,
    align: align || 'left', valign: valign || 'top', font_size: fs || 10, color: color || '#0F172A', visible: true,
  })
  return {
    project: {
      articul: 'HF#260924_104500',
      articul_locked: true,
      product: 'Шкаф купе, Тумба прикроватная, Зеркало',
      place: 'Прихожая и Спальня',
      adress: 'г. Москва, ул. Арбат, д. 24, кв. 12',
      materials: 'Корпус — ЛДСП 16 мм, фасады — MDF эмаль, фурнитура — Blum Legrabox',
      lighting: 'LED-подсветка 3000K, встраиваемая техника Bosch',
      commercial: false,
    },
    customer: {
      id: 'CUST-2609241045',
      name: 'Алексей Смирнов',
      phone: '+7 (999) 123-45-67',
      email: 'alex@example.com',
    },
    workflow: {
      author: 'Иванов И.И.',
      price: '245 000',
      start_date: '2026-09-01',
      end_date: '2026-09-30',
      total_duration: '14 дней / 65 часов',
      version: '02',
      revision: '003',
      rate: '1500 руб/ч',
      last_edit: 'Добавлены замки и скорректированы габариты тумбы',
      stadia,
    },
    project_info: {},
    scenes: scenesList,
    history,
    pdf_settings: {
      page_size: 'A3',
      page_layout: 'landscape',
      margin_mm: 5,
      show_aspect_overlay: true,
      image_aspect_ratio: '4:3',
      font_family: 'Sofia Sans Condensed',
      font_weight: 'normal',
      font_width: 'condensed',
      layout_render_mode: 'image',
      image_format: 'png',
      render_quality: 'medium',
      scale_multiplier: '2.0',
      save_layout_file: true,
      save_skp_backup: true,
      antialias: true,
      master_template_enabled: false,
      master_template_key: '',
      language: 'ru',
      custom_layouts: {
        cover: {
          name: 'Титульный лист (Cover)', _name: 'Титульный лист (Cover)', description: 'Обложка проекта',
          image_4_3: { x: 25, y: 12, w: 50, h: 82, visible: true, content: 'render_viewport', show_background: false, aspect_ratio: '4:3', scale_pct: 80 },
          params: [
            param('project.furniture_name', '', 'left', 'top', 24, '#0F172A'),
            param('project.address', '', 'left', 'top', 11, '#334155'),
            param('workflow.author', '', 'left', 'top', 11, '#334155'),
          ],
          line_gap: 2.5, line_enabled: false,
        },
        explain: {
          name: 'Содержание и ведомость (Explain)', _name: 'Содержание и ведомость (Explain)', description: 'Пояснительная записка',
          image_4_3: { x: 25, y: 12, w: 50, h: 82, visible: true, content: 'render_viewport', show_background: false, aspect_ratio: '4:3', scale_pct: 60 },
          params: [
            param('page.toc', '', 'left', 'top', 10, '#0F172A'),
            {
              id: 'g_materials', group: true, direction: 'horizontal', label: '', show_label: false,
              align: 'left', valign: 'bottom', font_size: 10, color: '#0F172A', visible: true,
              params: [
                { id: 'c_1', source: 'project.materials', label: '', show_label: true },
                { id: 'c_2', source: 'project.lighting', label: '', show_label: true },
              ],
            },
          ],
          line_gap: 2.5, line_enabled: true,
        },
        visual: {
          name: 'Визуализация (Visual)', _name: 'Визуализация (Visual)', description: 'Визуализация',
          image_4_3: { x: 25, y: 12, w: 50, h: 82, visible: true, content: 'render_viewport', show_background: false, aspect_ratio: '16:9', scale_pct: 100 },
          params: [param('scene.name', '', 'center', 'bottom', 14, '#0F172A')],
          line_gap: 2.5, line_enabled: false,
        },
        general: {
          name: 'Общий вид (General)', _name: 'Общий вид (General)', description: 'Техническая схема',
          image_4_3: { x: 25, y: 12, w: 50, h: 82, visible: true, content: 'render_viewport', show_background: false, aspect_ratio: '16:9', scale_pct: 100 },
          params: [],
          line_gap: 2.5, line_enabled: false,
        },
      },
    },
    directories: [
      { path: 'U:/dn1code/projects/specifications', title: 'Рабочие спецификации', description: 'Чертежи раскроя, список кромки и фурнитуры Blum' },
      { path: 'U:/dn1code/projects/photos', title: 'Фотографии объекта', description: 'Замеры стен, розеток и вентиляции' },
    ],
    api_targets: ['https://example.com/api/projects?token=dev'],
    template_sets: [
      { name: 'Кухни', saved_at: '2026-08-14 10:00:00', templates_count: 4 },
      { name: 'Шкафы', saved_at: '2026-07-02 16:30:00', templates_count: 3 },
    ],
    plugin_version: '2.9.0-dev',
    vips_available: true,
  }
}

function buildStatsPayload(empty, state) {
  const now = new Date()
  const dm = (d) => pad(d.getDate()) + '.' + pad(d.getMonth() + 1)
  if (empty) {
    return {
      articul: state?.project?.articul || 'HF#260924_104500',
      product: '',
      total_duration: '',
      saved_at: '',
      report: {
        total_seconds: 0, today_seconds: 0, weeks3_seconds: 0, month_seconds: 0,
        today: `${pad(now.getDate())}.${pad(now.getMonth() + 1)}.${now.getFullYear()}`,
        first_tracked: null, last_tracked: null, empty: true,
        series: { hourly: [], daily: [], monthly: [], yearly: [] },
      },
    }
  }
  const hourly = []
  for (let h = 0; h < 24; h++) hourly.push({ label: pad(h) + ':00', seconds: h >= 9 && h < 13 ? 1800 : 0 })
  const daysRu = ['Вс', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб']
  const daily = []
  for (let i = 20; i >= 0; i--) {
    const d = new Date(now)
    d.setDate(now.getDate() - i)
    const weekend = d.getDay() === 0 || d.getDay() === 6
    daily.push({ label: daysRu[d.getDay()] + ' ' + dm(d), seconds: weekend ? 0 : 9000 + ((i * 7919) % 7200), weekend })
  }
  const monthsRu = ['Янв', 'Фев', 'Мар', 'Апр', 'Май', 'Июн', 'Июл', 'Авг', 'Сен', 'Окт', 'Ноя', 'Дек']
  const monthly = []
  for (let i = 11; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1)
    monthly.push({ label: monthsRu[d.getMonth()] + ' ' + d.getFullYear(), seconds: 120000 + ((i * 9973) % 90000) })
  }
  const yearly = []
  for (let y = now.getFullYear() - 3; y <= now.getFullYear(); y++) {
    yearly.push({ label: String(y), seconds: y === now.getFullYear() ? 540000 : 800000 + (y % 7) * 40000 })
  }
  return {
    articul: state?.project?.articul || 'HF#260924_104500',
    product: state?.project?.product || '',
    total_duration: '14 дней / 65 часов',
    saved_at: `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())} ${pad(now.getHours())}:${pad(now.getMinutes())}`,
    report: {
      total_seconds: 2160000, today_seconds: 7200, weeks3_seconds: 148500, month_seconds: 238500,
      today: `${pad(now.getDate())}.${pad(now.getMonth() + 1)}.${now.getFullYear()}`,
      first_tracked: '2026-06-02', last_tracked: now.toISOString().slice(0, 10), empty: false,
      series: { hourly, daily, monthly, yearly },
    },
  }
}

// Текущее состояние стора для ответов, зависящих от данных
export function mockRubyCall(action, param) {
  if (action === 'getData') {
    delay(() => window.app && window.app.loadData(buildGetDataPayload()))
    return
  }
  console.log(`[Mock Ruby Call] ${action}`, param)

  const app = () => window.app
  switch (action) {
    case 'refreshScenes':
      delay(() => app().onScenesRefreshed && app().onScenesRefreshed([]))
      break
    case 'getSceneThumbnails':
      delay(() => app().onSceneThumbnailsLoaded && app().onSceneThumbnailsLoaded({}))
      break
    case 'getWorkStats':
      delay(() => app().onWorkStats && app().onWorkStats(buildStatsPayload(false)))
      break
    case 'resetWorkStats':
      delay(() => app().onWorkStats && app().onWorkStats(buildStatsPayload(true)))
      break
    case 'getFolderFiles': {
      let p = param
      try { p = typeof param === 'string' ? JSON.parse(param) : param } catch (e) { /* noop */ }
      delay(() => {
        app().onFolderFilesLoaded && app().onFolderFilesLoaded({
          index: p.index,
          path: p.path,
          exists: true,
          full_path: p.path,
          files: [
            { name: 'photo_preview_01.jpg', path: p.path + '/photo_01.jpg', url: '', size: 245760, ext: 'JPG', is_image: true },
            { name: 'room_dimension_plan.pdf', path: p.path + '/plan.pdf', url: '', size: 524288, ext: 'PDF', is_image: false },
          ],
        })
      }, 400)
      break
    }
    case 'saveData':
      delay(() => app().onAutoSaved && app().onAutoSaved('project.yaml'))
      break
    case 'saveProjectYaml':
      delay(() => app().showNotification && app().showNotification('project.yaml сохранён (мок)', 'success'))
      break
    case 'selectDirectory': {
      const idx = parseInt(param, 10) || 0
      delay(() => app().onDirectorySelected && app().onDirectorySelected(idx, 'U:/dn1code/projects/new_folder'))
      break
    }
    case 'createProjectFolder':
      delay(() => app().onProjectFolderCreated && app().onProjectFolderCreated('U:/projects/HF#000000_000000', true))
      break
    case 'generateCustomerId':
      delay(() => app().onCustomerIdGenerated && app().onCustomerIdGenerated(`CUST-${Date.now().toString(36).toUpperCase()}`))
      break
    case 'getTemplateSets':
      delay(() => app().onTemplateSetsUpdated && app().onTemplateSetsUpdated({ sets: buildGetDataPayload().template_sets }))
      break
    case 'deleteTemplateSet':
      delay(() => app().onTemplateSetsUpdated && app().onTemplateSetsUpdated({ sets: [] }))
      break
    case 'loadTemplateSet':
      delay(() => app().onTemplateSetLoaded && app().onTemplateSetLoaded({ custom_layouts: buildGetDataPayload().pdf_settings.custom_layouts }))
      break
    case 'saveTemplateSet':
      delay(() => {
        app().onTemplateSetsUpdated && app().onTemplateSetsUpdated({ sets: buildGetDataPayload().template_sets })
        app().showNotification && app().showNotification('Набор сохранён (мок)', 'success')
      })
      break
    case 'checkForUpdate':
      delay(() => app().onUpdateCheckResult && app().onUpdateCheckResult({ success: true, current_version: '2.9.0', dev_version: '2.9.0', update_available: false }))
      break
    case 'updateFromDev':
      delay(() => app().onDevUpdateResult && app().onDevUpdateResult({ success: true, same_dir: true, files_copied: 0, reloaded_at: new Date().toLocaleTimeString() }))
      break
    case 'toggleAspectOverlay':
      delay(() => app().syncOverlayState && app().syncOverlayState(true))
      break
    case 'startExport': {
      // Имитация прогресса экспорта
      let pct = 0
      const timer = setInterval(() => {
        pct += 12
        if (pct >= 100) {
          clearInterval(timer)
          app().updateProgress && app().updateProgress(100, 'Готово (мок)')
          delay(() => app().onExportSuccess && app().onExportSuccess('U:/mock/articul/pdf/preview.pdf', '004', 'U:/mock/preview_last.pdf'))
        } else {
          app().updateProgress && app().updateProgress(pct, `Рендер страниц… ${pct}% (мок)`)
        }
      }, 250)
      break
    }
    case 'importYaml':
      delay(() => app().loadData && app().loadData(buildGetDataPayload()))
      break
    default:
      // Остальные действия просто логируются
      break
  }
}
