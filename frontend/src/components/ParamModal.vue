<template>
  <BaseModal
    :open="ui.paramModal.visible"
    :title="ui.paramModal.title"
    card-class="modal-form-card param-modal-card"
    @close="close"
  >
    <div class="modal-header-row">
      <span class="modal-card-icon"><i class="modus-icons">tune</i></span>
      <h3>{{ ui.paramModal.title }}</h3>
    </div>
    <p class="field-hint">
      Выберите источник данных параметра. Шрифт, размер, выравнивания (задают место на странице), цвет и
      заголовок настраиваются в строке параметра.
    </p>

    <div class="form-group">
      <label for="paramModalSource">Источник данных *</label>
      <select id="paramModalSource" v-model="ui.paramModal.source" class="form-control" @change="refreshPreview">
        <optgroup v-for="g in ui.paramModal.sources" :key="g.title" :label="g.title">
          <option v-for="o in g.options" :key="o.value" :value="o.value">{{ o.label }}</option>
        </optgroup>
      </select>
      <div class="param-modal-preview" :class="{ empty: ui.paramModal.previewEmpty }">
        {{ ui.paramModal.preview }}
      </div>
    </div>

    <div class="form-group">
      <label
        for="paramModalLabel"
        title="Текст перед значением на листе (показ включается галкой «Заголовок» в строке параметра)"
      >Заголовок</label>
      <input
        id="paramModalLabel"
        v-model="ui.paramModal.label"
        type="text"
        class="form-control"
        :placeholder="ui.paramModal.labelPlaceholder"
        @keydown.enter.prevent="confirm"
      >
    </div>

    <div class="modal-actions">
      <button type="button" class="btn btn-secondary" @click="close">
        <i class="modus-icons">content_close</i> Отмена
      </button>
      <button type="button" class="btn btn-primary" @click="confirm">
        <i class="modus-icons">check_mark</i> Сохранить параметр
      </button>
    </div>
  </BaseModal>
</template>

<script setup>
import BaseModal from './BaseModal.vue'
import { ui } from '../store.js'

function close() {
  window.legacy?.closeParamModal?.()
}
function confirm() {
  window.legacy?.confirmParamModal?.()
}
function refreshPreview() {
  window.legacy?.updateParamModalPreview?.()
}
</script>
