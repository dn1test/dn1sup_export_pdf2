<template>
  <div class="settings-card">
    <div class="card-header">
      <div class="card-header-title-wrap">
        <span class="card-header-icon"><i class="modus-icons">folder</i></span>
        <span class="card-header-title">{{ t('dirs.title') }}</span>
      </div>
      <div class="card-header-buttons">
        <button type="button" class="btn btn-xs btn-secondary" @click="legacy('refreshDirectories')">
          <i class="modus-icons">refresh</i> {{ t('dirs.refresh') }}
        </button>
        <button type="button" class="btn btn-xs btn-primary" @click="legacy('addDirectory')">
          <i class="modus-icons">add_circle</i> {{ t('dirs.add') }}
        </button>
      </div>
    </div>
    <p class="field-hint">
      {{ t('dirs.hint') }}
    </p>

    <div class="directories-cards-container">
      <div v-if="!ui.directories.length" class="empty-dirs-placeholder">
        <div style="font-size: 32px; margin-bottom: 8px">
          <i class="modus-icons" style="font-size: 36px; color: var(--text-dim, #6a6e79)">folder</i>
        </div>
        <div style="font-weight: 600; color: var(--text-color); font-size: 14px">{{ t('dirs.emptyTitle') }}</div>
        <div style="font-size: 12px; color: var(--text-dim); margin-top: 4px">
          {{ t('dirs.emptyHint') }}
        </div>
      </div>

      <div
        v-for="(d, index) in ui.directories"
        :key="d.uid"
        class="directory-card"
        :class="{
          dragging: dragUid === index,
          'drag-over-top': overUid === index && overPos === 'top',
          'drag-over-bottom': overUid === index && overPos === 'bottom',
        }"
        :draggable="dragArm === d.uid"
        @dragstart="onDragStart($event, index)"
        @dragover="onDragOver($event, index)"
        @dragleave="clearOver"
        @drop="onDrop($event, index)"
        @dragend="clearDrag"
      >
        <!-- 1. HEADER: заголовок, путь (клик — выбрать папку), чекбокс отправки;
             справа — стрелки порядка, ручка перетаскивания и удаление -->
        <div class="dir-card-header">
          <div class="dir-header-left">
            <input
              v-model="d.title"
              type="text"
              class="form-control dir-title-input"
              :placeholder="t('dirs.titlePh')"
              :title="t('dirs.titleTitle')"
              @mousedown="dragArm = null"
              @change="commit()"
            >
            <button
              type="button"
              class="dir-path-text btn btn-xs btn-secondary"
              :class="{ empty: !d.path }"
              :title="d.path ? t('dirs.pathWithTitle', { path: d.path }) : t('dirs.pathNoPathTitle')"
              @click="selectDirectory(index)"
            >{{ d.path || t('dirs.pickFolder') }}</button>

            <div class="dir-header-actions">
              <label class="checkbox-label dir-send-server-label">
                <input
                  v-model="d.send_to_server"
                  type="checkbox"
                  :title="t('dirs.sendTitle')"
                  @change="commit()"
                >
                <span>{{ t('dirs.sendLabel') }}</span>
              </label>
            </div>
          </div>

          <div class="dir-header-right">
            <button
              type="button"
              class="btn-move-dir"
              :disabled="index === 0"
              :title="t('dirs.upTitle')"
              @click="moveUp(index)"
            >▲</button>
            <button
              type="button"
              class="btn-move-dir"
              :disabled="index === ui.directories.length - 1"
              :title="t('dirs.downTitle')"
              @click="moveDown(index)"
            >▼</button>
            <div
              class="dir-drag-handle"
              :title="t('dirs.dragTitle')"
              @mousedown="dragArm = d.uid"
              @mouseup="dragArm = null"
            >⠿</div>
            <button type="button" class="btn-icon btn-delete" :title="t('dirs.deleteTitle')" @click="removeDir(index)">
              <i class="modus-icons icon-close-cross" style="font-size: 11px">content_close</i>
            </button>
          </div>
        </div>

        <!-- 2. DESCRIPTION: спецификация раздела -->
        <div class="dir-section-desc">
          <textarea
            v-model="d.description"
            class="form-control dir-desc-textarea"
            rows="3"
            :placeholder="t('dirs.descPh')"
            @mousedown="dragArm = null"
            @input="commit()"
          ></textarea>
        </div>

        <!-- 3. PREVIEWS: файлы и предпросмотр -->
        <div class="dir-section-box dir-section-previews">
          <div class="dir-preview-header">
            <div class="dir-section-title">
              <span>
                <i class="modus-icons" style="font-size: 15px; vertical-align: -2px; margin-right: 4px">insert_photo</i>
                {{ t('dirs.filesLabel') }}
              </span>
              <code style="font-size: 11px; color: var(--text-dim); text-transform: none">{{ d.path || t('dirs.noPathCode') }}</code>
            </div>

            <div class="dir-preview-header-right">
              <div class="dir-thumb-size-group">
                <button
                  v-for="v in thumbVariants"
                  :key="v.key"
                  type="button"
                  class="dir-thumb-size-btn"
                  :class="{ active: d.thumb_size === v.key }"
                  :title="t(v.titleKey)"
                  @click="setThumbSize(d, v.key)"
                >{{ v.label }}</button>
              </div>
              <span class="badge badge-tag" :class="badgeClass(d.preview)">
                {{ badgeText(d.preview) }}
              </span>
              <button
                type="button"
                class="dir-open-folder-btn"
                :title="t('dirs.openTitle')"
                @click="openInExplorer(d)"
              >↗</button>
            </div>
          </div>

          <div class="dir-preview-grid" :class="`thumb-${d.thumb_size}`">
            <div v-if="d.preview.state === 'loading'" class="dir-empty-state" style="grid-column: 1 / -1">
              {{ t('dirs.stateLoading') }}
            </div>
            <div v-else-if="d.preview.state === 'timeout'" class="dir-empty-state" style="grid-column: 1 / -1; color: #b45309">
              {{ t('dirs.stateTimeout') }}
            </div>
            <div v-else-if="d.preview.state === 'missing'" class="dir-empty-state" style="grid-column: 1 / -1; color: #b45309">
              <i class="modus-icons" style="font-size: 16px; vertical-align: -2px; margin-right: 4px">warning</i>
              {{ t('dirs.stateMissing') }}
            </div>
            <div v-else-if="d.preview.state === 'nopath'" class="dir-empty-state" style="grid-column: 1 / -1">
              <i class="modus-icons" style="font-size: 16px; vertical-align: -2px; margin-right: 4px">folder</i>
              {{ t('dirs.stateNoPath') }}
            </div>
            <div v-else-if="d.preview.state === 'empty'" class="dir-empty-state" style="grid-column: 1 / -1">
              <i class="modus-icons" style="font-size: 16px; vertical-align: -2px; margin-right: 4px">folder</i>
              {{ t('dirs.stateEmpty') }}
            </div>

            <template v-else>
              <div
                v-for="file in d.preview.files"
                :key="file.path"
                class="dir-preview-item"
                :title="t('dirs.fileTitle', { name: file.name, size: formatFileSize(file.size) })"
                @click="callRuby('openFile', file.path)"
              >
                <div class="dir-preview-thumb-wrap">
                  <img
                    v-if="file.is_image && file.url && !file._err"
                    :src="file.url"
                    :alt="file.name"
                    loading="lazy"
                    @error="file._err = true"
                  >
                  <div v-else class="dir-preview-doc-icon">
                    <span v-if="file.is_image"><i class="modus-icons">insert_photo</i></span>
                    <span v-else v-html="docIcon(file.ext)"></span>
                    <span class="dir-preview-doc-ext">{{ file.is_image ? (file.ext || 'IMG') : file.ext }}</span>
                  </div>
                </div>
                <div class="dir-preview-meta">
                  <div class="dir-preview-name">{{ file.name }}</div>
                  <div class="dir-preview-size">{{ formatFileSize(file.size) }}</div>
                </div>
              </div>
            </template>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { ui, showToast } from '../store.js'
import { formatFileSize, getDocIcon as docIcon, pluralFiles } from '../format.js'
import { t } from '../i18n/index.js'

const thumbVariants = [
  { key: 'small', label: 'S', titleKey: 'dirs.thumbSmall' },
  { key: 'medium', label: 'M', titleKey: 'dirs.thumbMedium' },
  { key: 'large', label: 'L', titleKey: 'dirs.thumbLarge' },
]

// Отправка изменённого списка в legacy: state.directories + спецификации + автосейв
function commit() {
  window.legacy?.commitDirectories?.(
    ui.directories.map(({ uid, preview, _err, ...rest }) => ({ ...rest })),
  )
}

function legacy(fn, ...args) {
  window.legacy?.[fn]?.(...args)
}
function callRuby(action, param) {
  window.legacy?.callRuby?.(action, param)
}

function selectDirectory(index) {
  callRuby('selectDirectory', String(index))
}
function openInExplorer(d) {
  if (d.path) callRuby('openDirectoryPath', d.path)
  else showToast(t('dirs.toastNoFolder'), 'warning')
}

function moveUp(index) {
  if (index <= 0) return
  const [item] = ui.directories.splice(index, 1)
  ui.directories.splice(index - 1, 0, item)
  commit()
}
function moveDown(index) {
  if (index >= ui.directories.length - 1) return
  const [item] = ui.directories.splice(index, 1)
  ui.directories.splice(index + 1, 0, item)
  commit()
}
function removeDir(index) {
  ui.directories.splice(index, 1)
  commit()
}
function setThumbSize(d, key) {
  if (d.thumb_size === key) return
  d.thumb_size = key
  commit()
}

// Drag & Drop переупорядочивание (HTML5 DnD как в оригинале)
const dragArm = ref(null) // uid карточки, у которой зажата ручка — включает draggable
const dragUid = ref(null) // индекс перетаскиваемой карточки
const overUid = ref(null)
const overPos = ref(null)

function onDragStart(e, index) {
  dragUid.value = index
  e.dataTransfer.effectAllowed = 'move'
  e.dataTransfer.setData('text/plain', String(index))
}
function onDragOver(e, index) {
  e.preventDefault()
  e.dataTransfer.dropEffect = 'move'
  if (dragUid.value === null || dragUid.value === index) return
  const rect = e.currentTarget.getBoundingClientRect()
  const isTop = e.clientY - rect.top < rect.height / 2
  overUid.value = index
  overPos.value = isTop ? 'top' : 'bottom'
}
function clearOver() {
  overUid.value = null
  overPos.value = null
}
function clearDrag() {
  dragUid.value = null
  dragArm.value = null
  clearOver()
}
function onDrop(e, index) {
  e.preventDefault()
  e.stopPropagation()
  if (dragUid.value === null || dragUid.value === index) {
    clearDrag()
    return
  }
  const isTop = overPos.value === 'top'
  let dropIndex = isTop ? index : index + 1
  if (dragUid.value < dropIndex) dropIndex--
  const moved = ui.directories.splice(dragUid.value, 1)[0]
  ui.directories.splice(dropIndex, 0, moved)
  clearDrag()
  commit()
  showToast(t('dirs.toastMoved', { name: moved.title || t('dirs.folderWord'), n: dropIndex + 1 }), 'info')
}

function badgeText(preview) {
  switch (preview.state) {
    case 'loading': return t('dirs.badgeScanning')
    case 'timeout': return t('dirs.badgeTimeout')
    case 'missing': return t('dirs.badgeMissing')
    case 'nopath': return t('dirs.badgeNoFiles')
    case 'empty': return t('dirs.badgeNoFiles')
    default: return `${preview.count} ${pluralFiles(preview.count)}`
  }
}
function badgeClass(preview) {
  const ready = preview.state === 'ready' && preview.count > 0
  return ready ? 'badge-grid' : 'badge-list'
}
</script>
