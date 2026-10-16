import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import './style.css'
import { useTheme } from './composables/useTheme.js'
import { initBridge } from './bridge/sketchup.js'
import { vSpell } from './spellcheck/overlay.js'
import { ensureDicts } from './spellcheck/engine.js'

// Тему применяем до mount, чтобы диалог не мерцал светлым при тёмной настройке
useTheme().initTheme()

const app = createApp(App)
app.use(createPinia())
app.directive('spell', vSpell)
app.mount('#app')

// Мост к Ruby (window.app.* + пульс активности + запрос getData);
// в браузере отвечает dev-мок
initBridge()

// Словари спеллчекера тяжёлые (~1 c CPU) — греем после первого рендера диалога
setTimeout(ensureDicts, 1500)
