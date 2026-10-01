// Глобальный тост: отдельный реактивный модуль, чтобы сторы могли показывать
// уведомления без циклических импортов app-стора.

import { ref } from 'vue'

export const toast = ref({ visible: false, msg: '', type: 'success' })

let timer = null

export function showToast(msg, type = 'success') {
  toast.value = { visible: true, msg, type }
  clearTimeout(timer)
  timer = setTimeout(() => {
    toast.value.visible = false
  }, 3500)
}
