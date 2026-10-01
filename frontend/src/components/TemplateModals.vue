<template>
  <!-- Создание шаблона -->
  <BaseModal
    :open="!!m.newTemplate"
    :title="t('tm.newTitle')"
    card-class="modal-form-card"
    @close="closeNew"
  >
    <template v-if="m.newTemplate">
      <div class="modal-header-row">
        <span class="modal-card-icon"><i class="modus-icons">add_circle</i></span>
        <h3>{{ t('tm.newTitle') }}</h3>
      </div>
      <p class="field-hint">{{ t('tm.newHint') }}</p>
      <div class="form-group">
        <label for="inputNewTemplateName">{{ t('tm.nameLabel') }}</label>
        <input
          id="inputNewTemplateName"
          v-model="m.newTemplate.name"
          type="text"
          class="form-control"
          :placeholder="t('tm.newNamePh')"
          @keydown.enter.prevent="confirmNew"
        >
      </div>
      <div class="form-group">
        <label for="inputNewTemplateDescription">{{ t('tm.descHintLabel') }}</label>
        <input
          id="inputNewTemplateDescription"
          v-model="m.newTemplate.description"
          type="text"
          class="form-control"
          :placeholder="t('tm.newDescPh')"
          @keydown.enter.prevent="confirmNew"
        >
      </div>
      <div class="form-group">
        <label for="selectNewTemplateBase">{{ t('tm.baseLabel') }}</label>
        <select id="selectNewTemplateBase" v-model="m.newTemplate.base" class="form-control">
          <option v-for="b in m.newTemplate.bases" :key="b.key" :value="b.key">{{ b.name }}</option>
        </select>
      </div>
      <div class="modal-actions">
        <button type="button" class="btn btn-secondary" @click="closeNew"><i class="modus-icons">content_close</i> {{ t('common.cancel') }}</button>
        <button type="button" class="btn btn-primary" @click="confirmNew"><i class="modus-icons">check_mark</i> {{ t('tm.createBtn') }}</button>
      </div>
    </template>
  </BaseModal>

  <!-- Переименование шаблона -->
  <BaseModal
    :open="!!m.renameTemplate"
    :title="t('tm.renameTitle')"
    card-class="modal-form-card"
    @close="closeRename"
  >
    <template v-if="m.renameTemplate">
      <div class="modal-header-row">
        <span class="modal-card-icon"><i class="modus-icons">edit</i></span>
        <h3>{{ t('tm.renameTitle') }}</h3>
      </div>
      <p class="field-hint">{{ t('tm.renameHint', { name: m.renameTemplate.name }) }}</p>
      <div class="form-group">
        <label for="inputRenameTemplateName">{{ t('tm.nameLabel') }}</label>
        <input
          id="inputRenameTemplateName"
          v-model="m.renameTemplate.name"
          type="text"
          class="form-control"
          @keydown.enter.prevent="confirmRename"
        >
      </div>
      <div class="form-group">
        <label for="inputRenameTemplateDescription">{{ t('tm.descLabel') }}</label>
        <input
          id="inputRenameTemplateDescription"
          v-model="m.renameTemplate.description"
          type="text"
          class="form-control"
          @keydown.enter.prevent="confirmRename"
        >
      </div>
      <div class="modal-actions">
        <button type="button" class="btn btn-secondary" @click="closeRename"><i class="modus-icons">content_close</i> {{ t('common.cancel') }}</button>
        <button type="button" class="btn btn-primary" @click="confirmRename"><i class="modus-icons">check_mark</i> {{ t('tm.saveBtn') }}</button>
      </div>
    </template>
  </BaseModal>

  <!-- Удаление шаблона -->
  <BaseModal
    :open="!!m.deleteTemplate"
    :title="t('tm.deleteTitle')"
    @close="closeDelete"
  >
    <template v-if="m.deleteTemplate">
      <div class="modal-header-with-icon modal-header-danger">
        <div class="modal-badge-icon danger"><i class="modus-icons">delete</i></div>
        <div class="modal-header-text">
          <h3 class="modal-title">{{ t('tm.deleteTitle') }}</h3>
        </div>
      </div>
      <div class="modal-body-pad">
        <p>{{ m.deleteTemplate.msg || t('tm.deleteConfirm', { name: m.deleteTemplate.name }) }}</p>
        <p class="field-hint">{{ t('tm.deleteHint') }}</p>
      </div>
      <div class="modal-actions">
        <button type="button" class="btn btn-secondary" @click="closeDelete"><i class="modus-icons">content_close</i> {{ t('common.cancel') }}</button>
        <button type="button" class="btn btn-danger" @click="confirmDelete"><i class="modus-icons">delete</i> {{ t('tm.deleteBtn') }}</button>
      </div>
    </template>
  </BaseModal>

  <!-- Сохранение набора шаблонов -->
  <BaseModal
    :open="!!m.saveSet"
    :title="t('tm.saveSetTitle')"
    card-class="modal-form-card"
    @close="closeSaveSet"
  >
    <template v-if="m.saveSet">
      <div class="modal-header-row">
        <span class="modal-card-icon"><i class="modus-icons">layers</i></span>
        <h3>{{ t('tm.saveSetTitle') }}</h3>
      </div>
      <p class="field-hint">{{ t('tm.saveSetHint') }}</p>
      <div class="form-group">
        <label for="inputTemplateSetName">{{ t('tm.setLabel') }}</label>
        <input
          id="inputTemplateSetName"
          v-model="m.saveSet.name"
          type="text"
          class="form-control"
          :placeholder="t('tm.setPh')"
          @keydown.enter.prevent="confirmSaveSet"
        >
      </div>
      <div class="modal-actions">
        <button type="button" class="btn btn-secondary" @click="closeSaveSet"><i class="modus-icons">content_close</i> {{ t('common.cancel') }}</button>
        <button type="button" class="btn btn-primary" @click="confirmSaveSet"><i class="modus-icons">save</i> {{ t('tm.saveSetBtn') }}</button>
      </div>
    </template>
  </BaseModal>

  <!-- Подтверждение действия с набором -->
  <BaseModal
    :open="!!m.confirmSet"
    :title="m.confirmSet ? m.confirmSet.title : ''"
    @close="closeConfirmSet"
  >
    <template v-if="m.confirmSet">
      <div class="modal-header-with-icon" :class="{ 'modal-header-danger': m.confirmSet.danger }">
        <div class="modal-badge-icon" :class="{ danger: m.confirmSet.danger }"><i class="modus-icons">layers</i></div>
        <div class="modal-header-text">
          <h3 class="modal-title">{{ m.confirmSet.title }}</h3>
        </div>
      </div>
      <div class="modal-body-pad">
        <p>{{ m.confirmSet.msg }}</p>
        <p v-if="!m.confirmSet.danger" class="field-hint">
          {{ t('tm.confirmHint') }}
        </p>
      </div>
      <div class="modal-actions">
        <button type="button" class="btn btn-secondary" @click="closeConfirmSet"><i class="modus-icons">content_close</i> {{ t('common.cancel') }}</button>
        <button
          type="button"
          class="btn"
          :class="m.confirmSet.danger ? 'btn-danger' : 'btn-primary'"
          @click="confirmSet"
        >
          <i class="modus-icons">{{ m.confirmSet.danger ? 'delete' : 'check_mark' }}</i>
          {{ m.confirmSet.danger ? t('tm.deleteBtn') : (m.confirmSet.type === 'refresh' || m.confirmSet.type === 'overwrite' ? t('tm.btnOverwrite') : t('tm.btnLoad')) }}
        </button>
      </div>
    </template>
  </BaseModal>
</template>

<script setup>
import { computed } from 'vue'
import BaseModal from './BaseModal.vue'
import { ui } from '../store.js'
import { t } from '../i18n/index.js'

const m = computed(() => ui.tplModals)

function legacy(fn, ...args) {
  window.legacy?.[fn]?.(...args)
}

function closeNew() {
  ui.tplModals.newTemplate = null
}
function confirmNew() {
  const st = ui.tplModals.newTemplate
  if (st) legacy('confirmNewTemplate', st.name, st.base, st.description)
}
function closeRename() {
  legacy('closeRenameTemplateModal')
}
function confirmRename() {
  const st = ui.tplModals.renameTemplate
  if (st) legacy('confirmRenameTemplate', st.name, st.description)
}
function closeDelete() {
  legacy('closeDeleteTemplateModal')
}
function confirmDelete() {
  legacy('confirmDeleteTemplate')
}
function closeSaveSet() {
  legacy('closeSaveTemplateSetModal')
}
function confirmSaveSet() {
  const st = ui.tplModals.saveSet
  if (st) legacy('confirmSaveTemplateSet', st.name)
}
function closeConfirmSet() {
  legacy('closeConfirmTemplateSetModal')
}
function confirmSet() {
  legacy('confirmTemplateSetAction')
}
</script>

<style scoped>
.modal-body-pad {
  padding: 16px 20px;
}
</style>
