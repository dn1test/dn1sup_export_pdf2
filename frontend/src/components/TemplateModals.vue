<template>
  <!-- Создание шаблона -->
  <BaseModal
    :open="!!m.newTemplate"
    title="Новый шаблон страницы"
    card-class="modal-form-card"
    @close="closeNew"
  >
    <template v-if="m.newTemplate">
      <div class="modal-header-row">
        <span class="modal-card-icon"><i class="modus-icons">add_circle</i></span>
        <h3>Новый шаблон страницы</h3>
      </div>
      <p class="field-hint">Шаблон копирует видовой экран и параметры выбранной основы; название можно поменять в любой момент.</p>
      <div class="form-group">
        <label for="inputNewTemplateName">Название шаблона *</label>
        <input
          id="inputNewTemplateName"
          v-model="m.newTemplate.name"
          type="text"
          class="form-control"
          placeholder="Например: Страница с зоной замеров"
          @keydown.enter.prevent="confirmNew"
        >
      </div>
      <div class="form-group">
        <label for="inputNewTemplateDescription">Описание (подсказка в списках)</label>
        <input
          id="inputNewTemplateDescription"
          v-model="m.newTemplate.description"
          type="text"
          class="form-control"
          placeholder="Например: Для листов с обмерным планом"
          @keydown.enter.prevent="confirmNew"
        >
      </div>
      <div class="form-group">
        <label for="selectNewTemplateBase">Основа</label>
        <select id="selectNewTemplateBase" v-model="m.newTemplate.base" class="form-control">
          <option v-for="b in m.newTemplate.bases" :key="b.key" :value="b.key">{{ b.name }}</option>
        </select>
      </div>
      <div class="modal-actions">
        <button type="button" class="btn btn-secondary" @click="closeNew"><i class="modus-icons">content_close</i> Отмена</button>
        <button type="button" class="btn btn-primary" @click="confirmNew"><i class="modus-icons">check_mark</i> Создать шаблон</button>
      </div>
    </template>
  </BaseModal>

  <!-- Переименование шаблона -->
  <BaseModal
    :open="!!m.renameTemplate"
    title="Переименовать шаблон"
    card-class="modal-form-card"
    @close="closeRename"
  >
    <template v-if="m.renameTemplate">
      <div class="modal-header-row">
        <span class="modal-card-icon"><i class="modus-icons">edit</i></span>
        <h3>Переименовать шаблон</h3>
      </div>
      <p class="field-hint">Имя и описание шаблона «{{ m.renameTemplate.name }}». Сцены, использующие шаблон, сохраняют привязку.</p>
      <div class="form-group">
        <label for="inputRenameTemplateName">Название шаблона *</label>
        <input
          id="inputRenameTemplateName"
          v-model="m.renameTemplate.name"
          type="text"
          class="form-control"
          @keydown.enter.prevent="confirmRename"
        >
      </div>
      <div class="form-group">
        <label for="inputRenameTemplateDescription">Описание</label>
        <input
          id="inputRenameTemplateDescription"
          v-model="m.renameTemplate.description"
          type="text"
          class="form-control"
          @keydown.enter.prevent="confirmRename"
        >
      </div>
      <div class="modal-actions">
        <button type="button" class="btn btn-secondary" @click="closeRename"><i class="modus-icons">content_close</i> Отмена</button>
        <button type="button" class="btn btn-primary" @click="confirmRename"><i class="modus-icons">check_mark</i> Сохранить</button>
      </div>
    </template>
  </BaseModal>

  <!-- Удаление шаблона -->
  <BaseModal
    :open="!!m.deleteTemplate"
    title="Удаление шаблона"
    @close="closeDelete"
  >
    <template v-if="m.deleteTemplate">
      <div class="modal-header-with-icon modal-header-danger">
        <div class="modal-badge-icon danger"><i class="modus-icons">delete</i></div>
        <div class="modal-header-text">
          <h3 class="modal-title">Удаление шаблона</h3>
        </div>
      </div>
      <div class="modal-body-pad">
        <p>{{ m.deleteTemplate.msg || `Вы действительно хотите удалить шаблон «${m.deleteTemplate.name}»?` }}</p>
        <p class="field-hint">Сцены удалённого шаблона будут переключены на первый оставшийся шаблон.</p>
      </div>
      <div class="modal-actions">
        <button type="button" class="btn btn-secondary" @click="closeDelete"><i class="modus-icons">content_close</i> Отмена</button>
        <button type="button" class="btn btn-danger" @click="confirmDelete"><i class="modus-icons">delete</i> Удалить</button>
      </div>
    </template>
  </BaseModal>

  <!-- Сохранение набора шаблонов -->
  <BaseModal
    :open="!!m.saveSet"
    title="Сохранение набора шаблонов"
    card-class="modal-form-card"
    @close="closeSaveSet"
  >
    <template v-if="m.saveSet">
      <div class="modal-header-row">
        <span class="modal-card-icon"><i class="modus-icons">layers</i></span>
        <h3>Сохранение набора шаблонов</h3>
      </div>
      <p class="field-hint">Набор сохраняет текущий список всех шаблонов страниц. Загрузив набор позже, вы мгновенно переключите оформление PDF под другой проект:</p>
      <div class="form-group">
        <label for="inputTemplateSetName">Название набора *</label>
        <input
          id="inputTemplateSetName"
          v-model="m.saveSet.name"
          type="text"
          class="form-control"
          placeholder="Например: Кухни, Шкафы-купе, Проект Иванов"
          @keydown.enter.prevent="confirmSaveSet"
        >
      </div>
      <div class="modal-actions">
        <button type="button" class="btn btn-secondary" @click="closeSaveSet"><i class="modus-icons">content_close</i> Отмена</button>
        <button type="button" class="btn btn-primary" @click="confirmSaveSet"><i class="modus-icons">save</i> Сохранить набор</button>
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
          Текущие шаблоны и их параметры будут заменены содержимым набора. Сцены отсутствующих в наборе шаблонов переключатся на первый доступный шаблон.
        </p>
      </div>
      <div class="modal-actions">
        <button type="button" class="btn btn-secondary" @click="closeConfirmSet"><i class="modus-icons">content_close</i> Отмена</button>
        <button
          type="button"
          class="btn"
          :class="m.confirmSet.danger ? 'btn-danger' : 'btn-primary'"
          @click="confirmSet"
        >
          <i class="modus-icons">{{ m.confirmSet.danger ? 'delete' : 'check_mark' }}</i>
          {{ m.confirmSet.danger ? 'Удалить' : (m.confirmSet.type === 'refresh' || m.confirmSet.type === 'overwrite' ? 'Перезаписать' : 'Загрузить') }}
        </button>
      </div>
    </template>
  </BaseModal>
</template>

<script setup>
import { computed } from 'vue'
import BaseModal from './BaseModal.vue'
import { ui } from '../store.js'

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
