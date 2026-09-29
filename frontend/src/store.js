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
