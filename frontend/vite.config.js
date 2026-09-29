import { fileURLToPath, URL } from 'node:url'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// Сборка пишется прямо в папку плагина, откуда её берёт Ruby (set_file)
// и скрипты update_from_dev / упаковки .rbz.
export default defineConfig({
  base: './',
  plugins: [vue()],
  build: {
    outDir: fileURLToPath(new URL('../dn1c_export_pdf2/dialog/html', import.meta.url)),
    emptyOutDir: true,
  },
})
