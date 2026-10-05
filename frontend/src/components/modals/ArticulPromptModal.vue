<template>
  <UiModal
    :open="app.articulPrompt.visible"
    :title="t('articulPrompt.title')"
    :subtitle="t('articulPrompt.subtitle')"
    :icon="HashIcon"
    width="xs"
    @close="app.closeArticulPrompt()"
  >
    <UiField :label="t('articulPrompt.label')">
      <input
        v-model="app.articulPrompt.value"
        type="text"
        spellcheck="false"
        class="h-8 w-full rounded-md border border-ink-200 bg-white px-2.5 font-mono text-[13px] text-ink-900 focus:border-accent-500 focus:outline-none focus:ring-2 focus:ring-accent-500/20"
        :placeholder="t('articulPrompt.ph')"
        @keydown.enter.prevent="app.confirmArticulPrompt()"
        @keydown.esc="app.closeArticulPrompt()"
      >
      <span class="text-[11px] text-ink-400">{{ t('articulPrompt.hint') }}</span>
    </UiField>
    <template #footer>
      <UiButton @click="app.closeArticulPrompt()">{{ t('common.cancel') }}</UiButton>
      <UiButton variant="success" :icon="CheckIcon" :title="t('articulPrompt.confirmTitle')" @click="app.confirmArticulPrompt()">
        {{ t('articulPrompt.confirm') }}
      </UiButton>
    </template>
  </UiModal>
</template>

<script setup>
import { Hash, Check } from '@lucide/vue'
import UiModal from '../ui/UiModal.vue'
import UiButton from '../ui/UiButton.vue'
import UiField from '../ui/UiField.vue'
import { t } from '../../i18n/index.js'
import { useAppStore } from '../../stores/app.js'

const app = useAppStore()
const HashIcon = Hash
const CheckIcon = Check
</script>
