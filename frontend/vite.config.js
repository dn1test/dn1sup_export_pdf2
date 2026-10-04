import { fileURLToPath, URL } from 'node:url'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'

// Сборка пишется прямо в папку плагина, откуда её берёт Ruby (set_file)
// и скрипты update_from_dev / упаковки .rbz.
export default defineConfig({
  base: './',
  plugins: [vue(), tailwindcss()],
  build: {
    outDir: fileURLToPath(new URL('../dn1sup_export_pdf2/dialog/html', import.meta.url)),
    emptyOutDir: true,
  },
})
