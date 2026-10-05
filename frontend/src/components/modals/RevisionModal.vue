<template>
  <UiModal
    :open="app.revisionModal.visible"
    :title="t('rev.title')"
    :subtitle="t('rev.subtitle')"
    :icon="PencilIcon"
    @close="app.cancelRevision()"
  >
    <div class="mb-3 grid grid-cols-2 gap-2">
      <div class="rounded-lg bg-ink-50 px-3 py-2">
        <div class="text-[11px] text-ink-400">{{ t('rev.exactDateTime') }}</div>
        <div class="font-mono text-[13px] text-ink-900">{{ app.revisionModal.dateTime }}</div>
      </div>
      <div class="rounded-lg bg-ink-50 px-3 py-2">
        <div class="text-[11px] text-ink-400">{{ t('rev.revisionNumber') }}</div>
        <div class="font-mono text-[13px] text-ink-900">
          {{ app.revisionModal.currRev }}
          <span class="text-ink-300">→</span>
          <span class="rounded bg-accent-50 px-1.5 py-0.5 font-semibold text-accent-700">{{ app.revisionModal.nextRev }}</span>
        </div>
      </div>
    </div>

    <UiField :label="t('rev.noteLabel')">
      <textarea
        ref="noteEl"
        v-model="app.revisionModal.note"
        rows="3"
        spellcheck="false"
        v-spell
        class="w-full resize-y rounded-md border border-ink-200 bg-white px-2.5 py-1.5 text-[13px] text-ink-900 focus:border-accent-500 focus:outline-none focus:ring-2 focus:ring-accent-500/20"
        :placeholder="t('rev.notePh')"
        @keydown="onKeydown"
      />
      <span class="text-[11px] text-ink-400">{{ t('rev.hint') }}</span>
    </UiField>

    <template #footer>
      <UiButton @click="app.cancelRevision()">{{ t('common.cancel') }}</UiButton>
      <UiButton :title="t('rev.skipTitle')" @click="app.skipRevision()">{{ t('rev.skip') }}</UiButton>
      <UiButton variant="success" :icon="SaveIcon" :title="t('rev.confirmTitle')" @click="app.confirmRevision()">
        {{ t('rev.confirm') }}
      </UiButton>
    </template>
  </UiModal>
</template>

<script setup>
import { nextTick, ref, watch } from 'vue'
import { Pencil, Save } from '@lucide/vue'
import UiModal from '../ui/UiModal.vue'
import UiButton from '../ui/UiButton.vue'
import UiField from '../ui/UiField.vue'
import { t } from '../../i18n/index.js'
import { useAppStore } from '../../stores/app.js'

const app = useAppStore()
const noteEl = ref(null)
const PencilIcon = Pencil
const SaveIcon = Save

watch(
  () => app.revisionModal.visible,
  (v) => {
    if (v) nextTick(() => noteEl.value?.focus())
  },
)

function onKeydown(e) {
  if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
    e.preventDefault()
    app.confirmRevision()
  } else if (e.key === 'Escape') {
    app.cancelRevision()
  }
}
</script>
