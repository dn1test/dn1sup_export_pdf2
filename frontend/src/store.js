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
})

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
