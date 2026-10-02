<template>
  <div class="flex h-full min-h-0">
    <TemplatesSidebar />

    <!-- Панель настроек текущего шаблона -->
    <div class="flex min-w-0 flex-1 flex-col bg-white">
      <!-- Заголовок панели -->
      <div class="flex shrink-0 items-center gap-2 border-b border-ink-200 px-3.5 py-2">
        <TuneIcon :size="14" class="text-ink-400" />
        <span class="text-[13px] font-semibold text-ink-900" :title="t('tse.hint')">{{ t('tpl.panelTitle') }}</span>
        <div class="ml-auto flex items-center gap-1.5">
          <UiButton size="xs" :icon="UndoIcon" :title="t('tpl.resetTitle')" @click="templates.reset()">
            {{ t('tpl.resetBtn') }}
          </UiButton>
          <UiButton size="xs" variant="danger-soft" :icon="TrashIcon" :title="t('tpl.deleteTitle')" @click="templates.openDelete(templates.currentKey)">
            {{ t('tpl.deleteBtn') }}
          </UiButton>
        </div>
      </div>

      <!-- Тулбар: имя шаблона, бейджи (шрифт и поля перенесены в строку параметров) -->
      <div class="flex shrink-0 flex-wrap items-center gap-x-3 gap-y-1.5 border-b border-ink-100 bg-ink-50/50 px-3.5 py-1.5">
        <div class="flex min-w-0 items-center gap-2">
          <span class="truncate text-[13px] font-medium text-ink-900">{{ templates.currentDef.name }}</span>
          <span class="shrink-0 rounded border border-ink-200 bg-white px-1.5 py-0.5 font-mono text-[10px] text-ink-500">
            {{ settings.pageSize }} {{ t(settings.pageLayout === 'portrait' ? 'tpl.pageBadgePortrait' : 'tpl.pageBadgeLandscape') }}
          </span>
          <span
            class="shrink-0 rounded px-1.5 py-0.5 text-[10px]"
            :class="templates.usageBadge.empty ? 'bg-ink-100 text-ink-400' : 'bg-accent-50 text-accent-700'"
            :title="templates.usageBadge.title"
          >{{ templates.usageBadge.text }}</span>
        </div>
      </div>

      <!-- Редактор параметров -->
      <TemplateSettingsEditor v-if="templates.currentKey" />
      <div v-else class="flex flex-1 items-center justify-center text-[13px] text-ink-400">
        {{ t('tse.empty') }}
      </div>
    </div>
  </div>
</template>

<script setup>
import { SlidersHorizontal, Undo2, Trash2 } from '@lucide/vue'
import UiButton from '../ui/UiButton.vue'
import TemplatesSidebar from './TemplatesSidebar.vue'
import TemplateSettingsEditor from './TemplateSettingsEditor.vue'
import { t } from '../../i18n/index.js'
import { useTemplatesStore } from '../../stores/templates.js'
import { useSettingsStore } from '../../stores/settings.js'

const templates = useTemplatesStore()
const settings = useSettingsStore()

const TuneIcon = SlidersHorizontal
const UndoIcon = Undo2
const TrashIcon = Trash2
</script>
