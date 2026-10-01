<template>
  <div>
    <!-- Send Project Card: подготовка снимков и отправка проекта на сервер -->
    <div class="settings-card">
      <div class="card-header">
        <span class="card-header-icon"><i class="modus-icons">file_upload</i></span>
        <span class="card-header-title">Отправка проекта</span>
      </div>
      <p class="field-hint">Подготовка WebP-снимков страниц и отправка проекта адресатам веб-интеграции:</p>
      <button
        type="button"
        class="btn btn-success"
        id="btnStartSend"
        title="Подготовить WebP-снимки и отправить проект адресатам"
        @click="send"
      >
        <i class="modus-icons">file_upload</i> Отправить
      </button>
    </div>

    <!-- Snapshots WebP Card: значения читает/пишет legacy по id -->
    <div class="settings-card">
      <div class="card-header">
        <span class="card-header-icon"><i class="modus-icons">insert_photo</i></span>
        <span class="card-header-title">Снимки страниц (WebP)</span>
      </div>
      <div class="form-grid">
        <div class="form-group" id="webpQualityGroup">
          <label for="selectWebpQuality">Качество WebP</label>
          <select id="selectWebpQuality" class="form-control">
            <option value="75">75 — компактнее</option>
            <option value="85" selected>85 — рекомендуемое</option>
            <option value="95">95 — выше качество</option>
            <option value="lossless">Lossless — без потерь</option>
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
          <span class="card-header-title">Адресаты веб-интеграции (api_targets)</span>
        </div>
        <button type="button" class="btn btn-xs btn-primary" @click="addTarget">
          <i class="modus-icons">add_circle</i> + Добавить URL
        </button>
      </div>
      <p class="field-hint">Список адресатов веб-интеграции для отправки и синхронизации данных проекта:</p>
      <div class="api-targets-container">
        <div v-if="!ui.apiTargets.length" class="empty-targets-placeholder">
          Адресаты API не заданы. Нажмите «+ Добавить URL», чтобы добавить адрес веб-интеграции.
        </div>
        <div v-for="(url, index) in ui.apiTargets" :key="'t' + index" class="api-target-card">
          <span class="api-target-icon"><i class="modus-icons">web_link</i></span>
          <span class="api-target-badge">#{{ index + 1 }}</span>
          <input
            v-model="ui.apiTargets[index]"
            type="text"
            class="form-control api-target-input"
            placeholder="https://domain.com/api/projects?token=..."
            title="URL адресата веб-интеграции"
            @input="commit(false)"
            @change="commit(true)"
          >
          <button type="button" class="btn-icon btn-delete" title="Удалить этот адрес API" @click="removeTarget(index)">
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

// trim=true — событие «change» (уход из поля): нормализуем значение как в оригинале
function commit(trim) {
  if (trim) {
    ui.apiTargets = ui.apiTargets.map((t) => String(t ?? '').trim())
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
