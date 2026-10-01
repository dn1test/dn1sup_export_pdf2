<template>
  <!-- Создание шаблона -->
  <UiModal :open="!!m.newTemplate" :title="t('tm.newTitle')" :icon="PlusIcon" @close="m.newTemplate = null">
    <template v-if="m.newTemplate">
      <p class="mb-3 text-[13px] text-ink-500">{{ t('tm.newHint') }}</p>
      <div class="flex flex-col gap-3">
        <UiField :label="t('tm.nameLabel')">
          <UiInput v-model="m.newTemplate.name" :placeholder="t('tm.newNamePh')" @enter="confirmNew" />
        </UiField>
        <UiField :label="t('tm.descHintLabel')">
          <UiInput v-model="m.newTemplate.description" :placeholder="t('tm.newDescPh')" @enter="confirmNew" />
        </UiField>
        <UiField :label="t('tm.baseLabel')">
          <UiSelect v-model="m.newTemplate.base">
            <option v-for="b in m.newTemplate.bases" :key="b.key" :value="b.key">{{ b.name }}</option>
          </UiSelect>
        </UiField>
      </div>
    </template>
    <template #footer>
      <UiButton @click="m.newTemplate = null">{{ t('common.cancel') }}</UiButton>
      <UiButton variant="primary" :icon="PlusIcon2" @click="confirmNew">{{ t('tm.createBtn') }}</UiButton>
    </template>
  </UiModal>

  <!-- Переименование шаблона -->
  <UiModal :open="!!m.renameTemplate" :title="t('tm.renameTitle')" :icon="PencilIcon" @close="m.renameTemplate = null">
    <template v-if="m.renameTemplate">
      <p class="mb-3 text-[13px] text-ink-500">{{ t('tm.renameHint', { name: m.renameTemplate.name }) }}</p>
      <div class="flex flex-col gap-3">
        <UiField :label="t('tm.nameLabel')">
          <UiInput v-model="m.renameTemplate.name" @enter="confirmRename" />
        </UiField>
        <UiField :label="t('tm.descLabel')">
          <UiInput v-model="m.renameTemplate.description" @enter="confirmRename" />
        </UiField>
      </div>
    </template>
    <template #footer>
      <UiButton @click="m.renameTemplate = null">{{ t('common.cancel') }}</UiButton>
      <UiButton variant="primary" :icon="CheckIcon" @click="confirmRename">{{ t('tm.saveBtn') }}</UiButton>
    </template>
  </UiModal>

  <!-- Удаление шаблона -->
  <UiModal :open="!!m.deleteTemplate" :title="t('tm.deleteTitle')" :icon="TrashIcon" danger width="xs" @close="m.deleteTemplate = null">
    <template v-if="m.deleteTemplate">
      <p class="text-[13px] text-ink-700">{{ t('tm.deleteConfirm', { name: m.deleteTemplate.name }) }}</p>
      <p class="mt-2 text-[11px] text-ink-400">{{ t('tm.deleteHint') }}</p>
    </template>
    <template #footer>
      <UiButton @click="m.deleteTemplate = null">{{ t('common.cancel') }}</UiButton>
      <UiButton variant="danger" :icon="TrashIcon2" @click="templates.confirmDelete()">{{ t('tm.deleteBtn') }}</UiButton>
    </template>
  </UiModal>

  <!-- Сохранение набора шаблонов -->
  <UiModal :open="!!m.saveSet" :title="t('tm.saveSetTitle')" :icon="LayersIcon" @close="m.saveSet = null">
    <template v-if="m.saveSet">
      <p class="mb-3 text-[13px] text-ink-500">{{ t('tm.saveSetHint') }}</p>
      <UiField :label="t('tm.setLabel')">
        <UiInput v-model="m.saveSet.name" :placeholder="t('tm.setPh')" @enter="templates.confirmSaveSet(m.saveSet?.name)" />
      </UiField>
    </template>
    <template #footer>
      <UiButton @click="m.saveSet = null">{{ t('common.cancel') }}</UiButton>
      <UiButton variant="primary" :icon="SaveIcon" @click="templates.confirmSaveSet(m.saveSet?.name)">{{ t('tm.saveSetBtn') }}</UiButton>
    </template>
  </UiModal>

  <!-- Подтверждение действия с набором -->
  <UiModal
    :open="!!m.confirmSet"
    :title="m.confirmSet ? m.confirmSet.title : ''"
    :icon="LayersIcon2"
    :danger="!!m.confirmSet && m.confirmSet.danger"
    width="xs"
    @close="m.confirmSet = null"
  >
    <template v-if="m.confirmSet">
      <p class="text-[13px] text-ink-700">{{ m.confirmSet.msg }}</p>
      <p v-if="!m.confirmSet.danger" class="mt-2 text-[11px] text-ink-400">{{ t('tm.confirmHint') }}</p>
    </template>
    <template #footer>
      <UiButton @click="m.confirmSet = null">{{ t('common.cancel') }}</UiButton>
      <UiButton
        :variant="m.confirmSet && m.confirmSet.danger ? 'danger' : 'primary'"
        :icon="m.confirmSet && m.confirmSet.danger ? TrashIcon3 : CheckIcon2"
        @click="templates.confirmSetAction()"
      >
        {{
          m.confirmSet && m.confirmSet.danger
            ? t('tm.deleteBtn')
            : m.confirmSet && (m.confirmSet.type === 'refresh' || m.confirmSet.type === 'overwrite')
              ? t('tm.btnOverwrite')
              : t('tm.btnLoad')
        }}
      </UiButton>
    </template>
  </UiModal>
</template>

<script setup>
import { computed } from 'vue'
import { Plus, Pencil, Trash, Check, Layers, Save } from '@lucide/vue'
import UiModal from '../ui/UiModal.vue'
import UiButton from '../ui/UiButton.vue'
import UiField from '../ui/UiField.vue'
import UiInput from '../ui/UiInput.vue'
import UiSelect from '../ui/UiSelect.vue'
import { t } from '../../i18n/index.js'
import { useTemplatesStore } from '../../stores/templates.js'

const templates = useTemplatesStore()
const m = computed(() => templates.modals)

const PlusIcon = Plus
const PlusIcon2 = Plus
const PencilIcon = Pencil
const TrashIcon = Trash
const TrashIcon2 = Trash
const TrashIcon3 = Trash
const CheckIcon = Check
const CheckIcon2 = Check
const LayersIcon = Layers
const LayersIcon2 = Layers
const SaveIcon = Save

function confirmNew() {
  const st = m.value.newTemplate
  if (st) templates.confirmNewTemplate(st.name, st.base, st.description)
}
function confirmRename() {
  const st = m.value.renameTemplate
  if (st) templates.confirmRename(st.name, st.description)
}
</script>
