<template>
  <div class="flex flex-col gap-3">
    <!-- Отправка проекта + Снимки WebP: ряд из двух карточек без прокрутки -->
    <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
      <!-- Отправка проекта -->
      <UiCard :title="t('send.title')">
        <template #icon><SendIcon :size="14" /></template>
        <p class="mb-3 text-[11px] leading-tight text-ink-400">{{ t('send.hint') }}</p>
        <UiButton variant="success" size="md" class="w-full" :icon="SendIcon2" :title="t('send.sendTitle')" @click="app.startSend()">
          {{ t('send.sendBtn') }}
        </UiButton>
      </UiCard>

      <!-- Снимки WebP -->
      <UiCard :title="t('send.webpTitle')">
        <template #icon><ImageIcon :size="14" /></template>
        <UiField :label="t('send.webpQualityLabel')" :hint="settings.vipsAvailable ? t('send.vipsOk') : t('send.vipsMissing')">
          <UiSelect v-model="settings.webpQuality" @update:model-value="notifyChange()">
            <option value="75">{{ t('send.webp75') }}</option>
            <option value="85">{{ t('send.webp85') }}</option>
            <option value="95">{{ t('send.webp95') }}</option>
            <option value="lossless">{{ t('send.webpLossless') }}</option>
          </UiSelect>
        </UiField>
      </UiCard>
    </div>

    <!-- Адресаты API: на всю ширину — длинным URL нужна ширина ряда -->
    <UiCard :title="t('send.targetsTitle')">
      <template #icon><GlobeIcon :size="14" /></template>
      <template #actions>
        <UiButton size="xs" variant="primary" :icon="PlusIcon" @click="addTarget">{{ t('send.addBtn') }}</UiButton>
      </template>
      <p class="mb-2.5 text-[11px] text-ink-400">{{ t('send.targetsHint') }}</p>
      <div class="flex flex-col gap-1.5">
        <div v-if="!settings.apiTargets.length" class="rounded-md border border-dashed border-ink-200 py-4 text-center text-xs text-ink-400">
          {{ t('send.targetsEmpty') }}
        </div>
        <div
          v-for="(url, index) in settings.apiTargets"
          :key="'t' + index"
          class="flex items-center gap-2"
        >
          <span class="flex size-6 shrink-0 items-center justify-center rounded-md bg-ink-100 font-mono text-[10px] text-ink-500">
            {{ index + 1 }}
          </span>
          <UiInput
            v-model="settings.apiTargets[index]"
            :spellcheck="false"
            class="flex-1 font-mono text-xs"
            placeholder="https://domain.com/api/projects?token=..."
            :title="t('send.urlTitle')"
            @change="commit(true)"
            @update:model-value="commit(false)"
          />
          <UiButton size="xs" variant="ghost" :icon="XIcon" :title="t('send.deleteTargetTitle')" @click="removeTarget(index)" />
        </div>
      </div>
    </UiCard>
  </div>
</template>

<script setup>
import { nextTick } from 'vue'
import { Send, Image as ImageIcon, Globe, Plus, X } from '@lucide/vue'
import UiCard from '../ui/UiCard.vue'
import UiField from '../ui/UiField.vue'
import UiSelect from '../ui/UiSelect.vue'
import UiInput from '../ui/UiInput.vue'
import UiButton from '../ui/UiButton.vue'
import { t } from '../../i18n/index.js'
import { useAppStore } from '../../stores/app.js'
import { useSettingsStore } from '../../stores/settings.js'
import { notifyChange } from '../../stores/autosave.js'

const app = useAppStore()
const settings = useSettingsStore()

const SendIcon = Send
const SendIcon2 = Send
const GlobeIcon = Globe
const PlusIcon = Plus
const XIcon = X

// trim=true — уход из поля: нормализуем значения (как в оригинале)
function commit(trim) {
  if (trim) {
    settings.apiTargets = settings.apiTargets.map((u) => String(u ?? '').trim())
  }
  notifyChange()
}
function addTarget() {
  settings.apiTargets.push('')
  notifyChange()
  nextTick(() => {
    const inputs = document.querySelectorAll('.font-mono.text-xs')
    // фокус на последний инпут списка адресатов
    if (inputs.length) inputs[inputs.length - 1].focus()
  })
}
function removeTarget(index) {
  settings.apiTargets.splice(index, 1)
  notifyChange()
}
</script>
