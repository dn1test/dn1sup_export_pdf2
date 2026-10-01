import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import './style.css'
import { initBridge } from './bridge/sketchup.js'

const app = createApp(App)
app.use(createPinia())
app.mount('#app')

// Мост к Ruby (window.app.* + пульс активности + запрос getData);
// в браузере отвечает dev-мок
initBridge()
