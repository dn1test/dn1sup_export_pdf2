import { createApp } from 'vue'
import App from './App.vue'

const app = createApp(App)
app.mount('#app')

// Legacy vanilla GUI (переносится по вкладкам) выполняется после монтирования Vue,
// чтобы его getElementById/addEventListener находили элементы отрендеренного шаблона.
import('./legacy/app.js')
