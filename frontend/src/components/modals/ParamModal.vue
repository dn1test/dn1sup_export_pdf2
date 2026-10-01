<template>
  <UiModal
    :open="templates.paramModal.visible"
    :title="templates.paramModal.mode === 'edit' ? t('pm.titleEdit') : t('pm.titleCreate')"
    :icon="SlidersIcon"
    @close="templates.closeParamModal()"
  >
    <p class="mb-3 text-[13px] text-ink-500">{{ t('pm.hint') }}</p>

    <UiField :label="t('pm.sourceLabel')">
      <select
        v-model="templates.paramModal.source"
        class="h-8 w-full rounded-md border border-ink-200 bg-white px-1.5 text-[13px] text-ink-900 focus:border-accent-500 focus:outline-none focus:ring-2 focus:ring-accent-500/20"
      >
        <optgroup v-for="g in templates.paramModalSources" :key="g.title" :label="g.title">
          <option v-for="o in g.options" :key="o.value" :value="o.value">{{ o.label }}</option>
        </optgroup>
      </select>
      <div
        class="rounded-md px-2.5 py-1.5 text-xs"
        :class="templates.paramModalPreview.empty ? 'bg-ink-50 text-ink-400' : 'bg-accent-50 text-accent-700'"
      >
        {{ templates.paramModalPreview.text }}
      </div>
    </UiField>

    <UiField :label="t('pm.labelLabel')" :label-title="t('pm.labelTitle')">
      <input
        v-model="templates.paramModal.label"
        type="text"
        class="h-8 w-full rounded-md border border-ink-200 bg-white px-2.5 text-[13px] text-ink-900 focus:border-accent-500 focus:outline-none focus:ring-2 focus:ring-accent-500/20"
        :placeholder="templates.paramModalLabelPlaceholder"
        @keydown.enter.prevent="templates.confirmParamModal()"
      >
    </UiField>

    <template #footer>
      <UiButton @click="templates.closeParamModal()">{{ t('common.cancel') }}</UiButton>
      <UiButton variant="primary" :icon="CheckIcon" @click="templates.confirmParamModal()">{{ t('pm.saveBtn') }}</UiButton>
    </template>
  </UiModal>
</template>

<script setup>
import { SlidersHorizontal, Check } from '@lucide/vue'
import UiModal from '../ui/UiModal.vue'
import UiButton from '../ui/UiButton.vue'
import UiField from '../ui/UiField.vue'
import { t } from '../../i18n/index.js'
import { useTemplatesStore } from '../../stores/templates.js'

const templates = useTemplatesStore()
const SlidersIcon = SlidersHorizontal
const CheckIcon = Check
</script>
