<template>
  <footer class="flex shrink-0 items-center gap-2 border-t border-ink-200 bg-white px-3.5 py-2">
    <UiButton size="sm" :icon="SaveIcon" :title="t('footer.saveTitle')" @click="app.forcedSave()">
      {{ t('footer.saveBtn') }}
    </UiButton>
    <UiButton size="sm" :icon="DownloadIcon" :title="t('footer.importTitle')" @click="app.importYaml()">
      {{ t('footer.importYaml') }}
    </UiButton>
    <UiButton size="sm" :icon="UploadIcon" :title="t('footer.exportTitle')" @click="app.exportYaml()">
      {{ t('footer.exportYaml') }}
    </UiButton>

    <!-- Статус автосейва -->
    <div
      class="ml-2 flex items-center gap-1.5 text-[11px]"
      :class="statusCls"
      :title="autosaveTitle"
    >
      <span class="size-1.5 rounded-full" :class="dotCls" />
      <span>{{ statusText }}</span>
    </div>

    <div class="ml-auto flex items-center gap-3">
      <UiCheckbox v-model="settings.autoOpenPdf" :title="t('footer.autoOpenTitle')" @update:model-value="notifyChange()">
        {{ t('footer.autoOpen') }}
      </UiCheckbox>
      <UiButton variant="success" size="md" :icon="RocketIcon" :title="t('footer.exportBtn')" @click="app.startExport()">
        {{ t('footer.exportBtn') }}
      </UiButton>
    </div>
  </footer>
</template>

<script setup>
import { computed } from 'vue'
import { Save, Download, Upload, Rocket } from '@lucide/vue'
import UiButton from '../ui/UiButton.vue'
import UiCheckbox from '../ui/UiCheckbox.vue'
import { t } from '../../i18n/index.js'
import { useAppStore } from '../../stores/app.js'
import { useSettingsStore } from '../../stores/settings.js'
import { autosaveState, notifyChange } from '../../stores/autosave.js'

const app = useAppStore()
const settings = useSettingsStore()
const SaveIcon = Save
const DownloadIcon = Download
const UploadIcon = Upload
const RocketIcon = Rocket

const statusText = computed(() => {
  if (autosaveState.label) return autosaveState.label
  if (autosaveState.status === 'saving') return t('footer.autosaveSaving')
  return t('footer.autosaveText')
})

const autosaveTitle = computed(() => {
  if (autosaveState.status === 'saving') return t('footer.autosaveSavingTitle')
  if (autosaveState.status === 'saved') return t('footer.autosaveSavedTitle', { text: autosaveState.label })
  if (autosaveState.status === 'error') return t('footer.autosaveErrorTitle')
  return t('footer.autosaveTitle')
})

const statusCls = computed(() => ({
  saving: 'text-accent-600',
  saved: 'text-emerald-600',
  error: 'text-red-500',
}[autosaveState.status] || 'text-ink-400'))

const dotCls = computed(() => ({
  saving: 'animate-pulse bg-accent-500',
  saved: 'bg-emerald-500',
  error: 'bg-red-500',
}[autosaveState.status] || 'bg-ink-300'))
</script>
