import { reactive } from 'vue'

// Единый реактивный UI-store для новых Vue-компонентов.
// Бизнес-логика остаётся в legacy/app.js: он пишет состояние сюда,
// а Vue-компоненты читают его и отправляют действия обратно через window.legacy.
export const ui = reactive({
  toast: { visible: false, msg: '', type: 'success', icon: 'check-circle' },
  paramModal: {
    visible: false,
    mode: 'create',
    id: null,
    tplKey: null,
    title: '',
    source: '',
    label: '',
    sources: [],
    preview: '',
    previewEmpty: true,
    labelPlaceholder: '',
  },
  // Вкладка «Папки»: записи пишет legacy (refreshDirectoriesUI), мутации —
  // DirectoriesTab.vue с последующим commitDirectories() в legacy.
  directories: [],
  // Вкладка «История»: ui.history = [{ uid, item }], где item — тот же объект,
  // что и в state.history (прокси Vue пишет данные насквозь в legacy-state).
  history: [],
  // Вкладка «Отправка»: список адресатов API (строки-URL)
  apiTargets: [],
  // Вкладка «Проект»: стадии { uid, item } (write-through в state.workflow.stadia)
  stadia: [],
  // Вкладка «Страницы»: строки таблицы { uid, item } (write-through в state.scenes),
  // эскизы (имя сцены / original_name / индекс → dataURL), выделенная строка,
  // текущий шаблон редактора и список шаблонов для селекта «Шаблон»
  scenes: [],
  sceneThumbnails: {},
  selectedSceneIndex: -1,
  currentTemplate: '',
  templateOptions: [],
  // Вкладка «Шаблоны»: список шаблонов { key, name, sub }, наборы
  // { name, sub } и состояние пяти модалок. Бизнес-логика — в legacy.
  templates: [],
  templateSets: [],
  // Редактор параметров шаблона (TemplateSettingsEditor.vue): снимок данных
  // с вычисленными подписями (_label/_shownLabel/_preview/_zone); каждая мутация
  // идёт через legacy-мутатор состояния и завершается ре-синком
  tplEditor: { tplKey: '', lineGap: 2.5, lineEnabled: false, params: [] },
  tplModals: {
    newTemplate: null,   // { name, description, base, bases: [{key, name}] } | null
    renameTemplate: null, // { key, name, description } | null
    deleteTemplate: null, // { key, name, msg } | null
    saveSet: null,        // { name } | null
    confirmSet: null,     // { type: 'load'|'overwrite'|'delete'|'refresh', name, title, msg, danger } | null
  },
  // Вкладка «Статистика»: отчёт Ruby (getWorkStats → onWorkStats) — сводки и
  // серии графиков работы над проектом; seq — триггер перерисовки диаграммы
  stats: { loaded: false, error: '', articul: '', product: '', savedAt: '', report: null, seq: 0 },
})

let dirUidSeq = 1
export function nextDirUid() {
  return 'dir-' + dirUidSeq++
}

export function defaultDirPreview() {
  return { state: 'loading', files: [], count: 0 }
}

let toastTimer = null
export function showToast(msg, type = 'success') {
  const icon =
    type === 'error' ? 'cancel' : type === 'warning' ? 'warning' : type === 'info' ? 'info' : 'check-circle'
  ui.toast = { visible: true, msg, type, icon }
  clearTimeout(toastTimer)
  toastTimer = setTimeout(() => {
    ui.toast.visible = false
  }, 3500)
}
