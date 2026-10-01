<template>
  <div class="tab-stack">
    <!-- Send Project Card: подготовка снимков и отправка проекта на сервер -->
    <div class="settings-card">
      <div class="card-header">
        <span class="card-header-icon"><i class="modus-icons">file_upload</i></span>
        <span class="card-header-title">{{ t('send.title') }}</span>
      </div>
      <p class="field-hint">{{ t('send.hint') }}</p>
      <button
        type="button"
        class="btn btn-success"
        id="btnStartSend"
        :title="t('send.sendTitle')"
        @click="send"
      >
        <i class="modus-icons">file_upload</i> {{ t('send.sendBtn') }}
      </button>
    </div>

    <!-- Snapshots WebP Card: значения читает/пишет legacy по id -->
    <div class="settings-card">
      <div class="card-header">
        <span class="card-header-icon"><i class="modus-icons">insert_photo</i></span>
        <span class="card-header-title">{{ t('send.webpTitle') }}</span>
      </div>
      <div class="form-grid">
        <div class="form-group" id="webpQualityGroup">
          <label for="selectWebpQuality">{{ t('send.webpQualityLabel') }}</label>
          <select id="selectWebpQuality" class="form-control">
            <option value="75">{{ t('send.webp75') }}</option>
            <option value="85" selected>{{ t('send.webp85') }}</option>
            <option value="95">{{ t('send.webp95') }}</option>
            <option value="lossless">{{ t('send.webpLossless') }}</option>
          </select>
          <span id="hintWebpFormat" class="field-hint"></span>
        </div>
      </div>
    </div>

    <!-- Section: Адресаты API -->
    <div class="settings-card">
      <div class="card-header">
        <div class="card-header-title-wrap">
          <span class="card-header-icon"><i class="modus-icons">browser</i></span>
          <span class="card-header-title">{{ t('send.targetsTitle') }}</span>
        </div>
        <button type="button" class="btn btn-xs btn-primary" @click="addTarget">
          <i class="modus-icons">add_circle</i> {{ t('send.addBtn') }}
        </button>
      </div>
      <p class="field-hint">{{ t('send.targetsHint') }}</p>
      <div class="api-targets-container">
        <div v-if="!ui.apiTargets.length" class="empty-targets-placeholder">
          {{ t('send.targetsEmpty') }}
        </div>
        <div v-for="(url, index) in ui.apiTargets" :key="'t' + index" class="api-target-card">
          <span class="api-target-icon"><i class="modus-icons">web_link</i></span>
          <span class="api-target-badge">#{{ index + 1 }}</span>
          <input
            v-model="ui.apiTargets[index]"
            type="text"
            class="form-control api-target-input"
            placeholder="https://domain.com/api/projects?token=..."
            :title="t('send.urlTitle')"
            @input="commit(false)"
            @change="commit(true)"
          >
          <button type="button" class="btn-icon btn-delete" :title="t('send.deleteTargetTitle')" @click="removeTarget(index)">
            <i class="modus-icons icon-close-cross" style="font-size: 11px">content_close</i>
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { nextTick } from 'vue'
import { ui } from '../store.js'
import { t } from '../i18n/index.js'

// trim=true — событие «change» (уход из поля): нормализуем значение как в оригинале
function commit(trim) {
  if (trim) {
    ui.apiTargets = ui.apiTargets.map((u) => String(u ?? '').trim())
  }
  window.legacy?.commitApiTargets?.([...ui.apiTargets])
}
function addTarget() {
  window.legacy?.addApiTarget?.()
  nextTick(() => {
    const inputs = document.querySelectorAll('.api-target-input')
    if (inputs.length) inputs[inputs.length - 1].focus()
  })
}
function removeTarget(index) {
  ui.apiTargets.splice(index, 1)
  window.legacy?.commitApiTargets?.([...ui.apiTargets])
}
// Отправка проекта: подготовка WebP-снимков и отправка (логика в legacy/app.js)
function send() {
  window.legacy?.startSend?.()
}
</script>
