<template>
  <UiModal
    :open="open"
    :title="t('help.title')"
    :subtitle="t('help.subtitle', { version: app.pluginVersion || '…' })"
    :icon="BookIcon"
    width="lg"
    @close="$emit('close')"
  >
    <div class="space-y-4 text-[12px] leading-relaxed text-ink-700">
      <!-- Что делает расширение -->
      <section class="space-y-1.5">
        <h4 class="text-[12px] font-semibold text-ink-900">{{ t('help.aboutTitle') }}</h4>
        <p>{{ t('help.aboutText') }}</p>
      </section>

      <!-- Подробно по разделам -->
      <section class="space-y-4">
        <h4 class="text-[12px] font-semibold text-ink-900">{{ t('help.sectionsTitle') }}</h4>
        <div v-for="id in sectionIds" :key="id" class="space-y-2 border-t border-ink-100 pt-3 first:border-t-0 first:pt-0">
          <h5 class="text-[12px] font-semibold text-accent-700">{{ t(`help.tab.${id}`) }}</h5>
          <template v-for="(block, bi) in sectionBlocks(id)" :key="bi">
            <ul v-if="block.bullets" class="list-disc space-y-1.5 pl-5">
              <li v-for="(item, ii) in block.bullets" :key="ii" class="leading-relaxed" v-html="item" />
            </ul>
            <p v-else class="leading-relaxed" v-html="block.html" />
          </template>
        </div>
      </section>

      <!-- Что лежит в папке артикула -->
      <section class="space-y-1.5">
        <h4 class="text-[12px] font-semibold text-ink-900">{{ t('help.treeTitle') }}</h4>
        <pre class="overflow-x-auto rounded-lg bg-ink-100 p-3 font-mono text-[11px] leading-relaxed text-ink-700">{{ t('help.treeText') }}</pre>
        <p class="text-[11px] text-ink-400">{{ t('help.treeNote') }}</p>
      </section>

      <!-- Интерфейс -->
      <section class="space-y-1.5">
        <h4 class="text-[12px] font-semibold text-ink-900">{{ t('help.uiTitle') }}</h4>
        <ul class="space-y-1.5 leading-relaxed">
          <li class="flex items-start gap-2">
            <HelpIcon :size="14" class="mt-0.5 shrink-0 text-ink-400" />
            <span>{{ t('help.uiHelp') }}</span>
          </li>
          <li class="flex items-start gap-2">
            <MoonIcon :size="14" class="mt-0.5 shrink-0 text-ink-400" />
            <span>{{ t('help.uiTheme') }}</span>
          </li>
          <li class="flex items-start gap-2">
            <RefreshIcon :size="14" class="mt-0.5 shrink-0 text-ink-400" />
            <span>{{ t('help.uiUpdate') }}</span>
          </li>
          <li class="flex items-start gap-2">
            <GlobeIcon :size="14" class="mt-0.5 shrink-0 text-ink-400" />
            <span>{{ t('help.uiLang') }}</span>
          </li>
        </ul>
      </section>
    </div>

    <template #footer>
      <UiButton variant="primary" @click="$emit('close')">{{ t('help.close') }}</UiButton>
    </template>
  </UiModal>
</template>

<script setup>
import { BookOpen, HelpCircle, Moon, RefreshCw, Globe } from '@lucide/vue'
import UiModal from '../ui/UiModal.vue'
import UiButton from '../ui/UiButton.vue'
import { t } from '../../i18n/index.js'
import { useAppStore } from '../../stores/app.js'

defineProps({
  open: { type: Boolean, default: false },
})
defineEmits(['close'])

const app = useAppStore()
// Порядок разделов — как вкладки в диалоге
const sectionIds = ['project', 'scenes', 'templates', 'directories', 'history', 'stats', 'settings', 'send']

// Текст раздела: абзацы разделены пустой строкой; абзац из строк,
// начинающихся с «•», рисуется списком-буллетами с отступами
function sectionBlocks(id) {
  return String(t(`help.tab.${id}.text`))
    .split(/\n\s*\n/)
    .map((b) => b.trim())
    .filter(Boolean)
    .map((b) => {
      const lines = b.split('\n').map((l) => l.trim()).filter(Boolean)
      if (lines.length > 1 && lines.every((l) => l.startsWith('•'))) {
        return { bullets: lines.map((l) => l.slice(1).trim()) }
      }
      return { html: lines.join('<br>') }
    })
}
const BookIcon = BookOpen
const HelpIcon = HelpCircle
const MoonIcon = Moon
const RefreshIcon = RefreshCw
const GlobeIcon = Globe
</script>
