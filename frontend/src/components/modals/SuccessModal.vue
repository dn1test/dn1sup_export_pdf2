<template>
  <UiModal :open="app.successModal.visible" :title="t('success.title')" :icon="CheckIcon" width="md" @close="app.successModal.visible = false">
    <div class="flex flex-col items-center gap-3 py-2">
      <span class="flex size-12 items-center justify-center rounded-full bg-emerald-50 text-emerald-600">
        <CheckCircle2Icon :size="26" />
      </span>
      <div class="w-full rounded-lg border border-ink-200 bg-ink-50 px-3 py-2 text-center">
        <div class="mb-0.5 text-[11px] text-ink-400">{{ t('success.pathLabel') }}</div>
        <p
          class="cursor-pointer break-all font-mono text-xs text-ink-700 hover:text-accent-700"
          :title="t('success.pathTitle')"
          @click="app.copyPdfPath()"
        >{{ app.successModal.pdfPath }}</p>
      </div>
    </div>
    <template #footer>
      <UiButton :icon="FolderIcon" @click="app.openExportedPdfFolder()">{{ t('success.openFolder') }}</UiButton>
      <UiButton variant="primary" :icon="CheckIcon2" @click="app.successModal.visible = false">{{ t('success.done') }}</UiButton>
    </template>
  </UiModal>
</template>

<script setup>
import { Check, CheckCircle2, Folder } from '@lucide/vue'
import UiModal from '../ui/UiModal.vue'
import UiButton from '../ui/UiButton.vue'
import { t } from '../../i18n/index.js'
import { useAppStore } from '../../stores/app.js'

const app = useAppStore()
const CheckIcon = Check
const CheckIcon2 = Check
const CheckCircle2Icon = CheckCircle2
const FolderIcon = Folder
</script>
