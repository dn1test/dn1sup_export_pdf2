<template>
  <div class="flex flex-col gap-3">
    <UiCard :title="t('dirs.title')" body-class="p-3.5">
      <template #icon><FolderIcon :size="14" /></template>
      <template #actions>
        <UiButton size="xs" :icon="RefreshIcon" @click="dirs.refreshAll()">{{ t('dirs.refresh') }}</UiButton>
        <UiButton size="xs" variant="primary" :icon="PlusIcon" @click="dirs.add()">{{ t('dirs.add') }}</UiButton>
      </template>
      <p v-if="!dirs.list.length" class="text-[13px] text-ink-400">{{ t('dirs.hint') }}</p>

      <div v-if="!dirs.list.length">
        <UiEmptyState :title="t('dirs.emptyTitle')" :hint="t('dirs.emptyHint')">
          <template #icon><FolderIcon :size="36" /></template>
        </UiEmptyState>
      </div>

      <div v-else class="flex flex-col gap-2.5">
        <div
          v-for="(d, index) in dirs.list"
          :key="d.uid"
          class="rounded-lg border bg-white transition-shadow"
          :class="[
            drag.rowClasses(index),
            'border-ink-200',
            drag.overIdx === index && (drag.overPos === 'top' ? 'shadow-[inset_0_2px_0_0_var(--color-accent-500)]' : 'shadow-[inset_0_-2px_0_0_var(--color-accent-500)]'),
          ]"
          :draggable="drag.dragArm.value === d.uid"
          @dragstart="drag.onDragStart($event, index)"
          @dragover="drag.onDragOver($event, index)"
          @dragleave="drag.clearOver()"
          @drop="drag.onDrop($event, index)"
          @dragend="drag.clearDrag()"
        >
          <!-- Шапка карточки -->
          <div class="flex flex-wrap items-center gap-2 border-b border-ink-100 px-2.5 py-2">
            <GripVerticalIcon
              :size="13"
              class="shrink-0 cursor-grab text-ink-300 hover:text-ink-500"
              :title="t('dirs.dragTitle')"
              @mousedown="drag.dragArm.value = d.uid"
              @mouseup="drag.dragArm.value = null"
            />
            <UiInput
              v-model="d.title"
              class="w-52"
              :placeholder="t('dirs.titlePh')"
              :title="t('dirs.titleTitle')"
              @mousedown="drag.dragArm.value = null"
              @update:model-value="commit"
            />
            <button
              type="button"
              class="flex h-7 min-w-0 flex-1 items-center gap-1.5 rounded-md border px-2.5 text-left font-mono text-[11px] transition-colors"
              :class="d.path
                ? 'border-ink-200 bg-ink-50 text-ink-600 hover:border-accent-300 hover:bg-accent-50'
                : 'border-dashed border-ink-300 text-ink-400 hover:border-accent-400 hover:text-accent-600'"
              :title="d.path ? t('dirs.pathWithTitle', { path: d.path }) : t('dirs.pathNoPathTitle')"
              @click="selectDirectory(index)"
            >
              <FolderOpenIcon :size="12" class="shrink-0" />
              <span class="truncate">{{ d.path || t('dirs.pickFolder') }}</span>
            </button>

            <div class="ml-auto flex shrink-0 items-center gap-1">
              <UiCheckbox v-model="d.send_to_server" :title="t('dirs.sendTitle')" @update:model-value="commit">
                {{ t('dirs.sendLabel') }}
              </UiCheckbox>
              <IconBtn :title="t('dirs.upTitle')" :disabled="index === 0" @click="moveUp(index)"><ChevronUpIcon :size="12" /></IconBtn>
              <IconBtn :title="t('dirs.downTitle')" :disabled="index === dirs.list.length - 1" @click="moveDown(index)"><ChevronDownIcon :size="12" /></IconBtn>
              <IconBtn :title="t('dirs.deleteTitle')" danger @click="dirs.remove(index)"><XIcon :size="12" /></IconBtn>
            </div>
          </div>

          <!-- Описание раздела -->
          <div class="px-2.5 py-2">
            <UiTextarea
              v-model="d.description"
              :rows="2"
              class="text-xs"
              :placeholder="t('dirs.descPh')"
              @mousedown="drag.dragArm.value = null"
              @update:model-value="commit"
            />
          </div>

          <!-- Превью файлов -->
          <div class="border-t border-ink-100 px-2.5 py-2">
            <div class="mb-2 flex items-center gap-2">
              <span class="flex items-center gap-1 text-[11px] font-medium text-ink-500">
                <ImageIcon2 :size="12" /> {{ t('dirs.filesLabel') }}
              </span>
              <code class="truncate font-mono text-[10px] text-ink-400">{{ d.path || t('dirs.noPathCode') }}</code>
              <div class="ml-auto flex items-center gap-1.5">
                <div class="flex rounded-md border border-ink-200 p-0.5">
                  <button
                    v-for="v in thumbVariants"
                    :key="v.key"
                    type="button"
                    class="rounded px-1.5 py-0.5 text-[10px] font-semibold transition-colors"
                    :class="d.thumb_size === v.key ? 'bg-accent-600 text-white' : 'text-ink-400 hover:text-ink-600'"
                    :title="t(v.titleKey)"
                    @click="setThumbSize(d, v.key)"
                  >{{ v.label }}</button>
                </div>
                <UiBadge :variant="badgeVariant(d.preview)">{{ badgeText(d.preview) }}</UiBadge>
                <IconBtn :title="t('dirs.openTitle')" @click="dirs.openExplorer(d)"><ExternalLinkIcon :size="12" /></IconBtn>
              </div>
            </div>

            <div class="grid gap-1.5" :class="gridCls(d.thumb_size)">
              <!-- Состояния сканирования -->
              <div v-if="d.preview.state === 'loading'" class="col-span-full flex items-center justify-center gap-2 rounded-md bg-ink-50 py-5 text-xs text-ink-400">
                <LoaderIcon :size="14" class="animate-spin" /> {{ t('dirs.stateLoading') }}
              </div>
              <div v-else-if="d.preview.state === 'timeout'" class="col-span-full rounded-md bg-amber-50 py-5 text-center text-xs text-amber-600">
                {{ t('dirs.stateTimeout') }}
              </div>
              <div v-else-if="d.preview.state === 'missing'" class="col-span-full flex items-center justify-center gap-2 rounded-md bg-amber-50 py-5 text-xs text-amber-600">
                <AlertIcon :size="14" /> {{ t('dirs.stateMissing') }}
              </div>
              <div v-else-if="d.preview.state === 'nopath'" class="col-span-full flex items-center justify-center gap-2 rounded-md bg-ink-50 py-5 text-xs text-ink-400">
                <FolderIcon2 :size="14" /> {{ t('dirs.stateNoPath') }}
              </div>
              <div v-else-if="d.preview.state === 'empty'" class="col-span-full flex items-center justify-center gap-2 rounded-md bg-ink-50 py-5 text-xs text-ink-400">
                <FolderIcon3 :size="14" /> {{ t('dirs.stateEmpty') }}
              </div>

              <!-- Файлы -->
              <template v-else>
                <button
                  v-for="file in d.preview.files"
                  :key="file.path"
                  type="button"
                  class="group flex flex-col overflow-hidden rounded-md border border-ink-200 bg-white transition-colors hover:border-accent-300"
                  :title="t('dirs.fileTitle', { name: file.name, size: formatFileSize(file.size) })"
                  @click="callRuby('openFile', file.path)"
                >
                  <div class="flex aspect-[4/3] w-full items-center justify-center overflow-hidden bg-ink-50">
                    <img
                      v-if="file.is_image && file.url && !file._err"
                      :src="file.url"
                      :alt="file.name"
                      loading="lazy"
                      class="h-full w-full object-cover"
                      @error="file._err = true"
                    >
                    <component :is="docIcon(file.ext)" v-else :size="22" class="text-ink-300" />
                  </div>
                  <div class="flex min-w-0 flex-col px-1.5 py-1">
                    <span class="truncate text-[10px] font-medium text-ink-700">{{ file.name }}</span>
                    <span class="font-mono text-[9px] text-ink-400">
                      {{ file.is_image ? (file.ext || 'IMG') : file.ext }} · {{ formatFileSize(file.size) }}
                    </span>
                  </div>
                </button>
              </template>
            </div>
          </div>
        </div>
      </div>
    </UiCard>
  </div>
</template>

<script setup>
import {
  Folder, FolderOpen, RefreshCw, Plus, GripVertical, ChevronUp, ChevronDown,
  X, ExternalLink, Image as ImageIcon, Loader2, AlertTriangle,
} from '@lucide/vue'
import UiCard from '../ui/UiCard.vue'
import UiButton from '../ui/UiButton.vue'
import UiInput from '../ui/UiInput.vue'
import UiTextarea from '../ui/UiTextarea.vue'
import UiCheckbox from '../ui/UiCheckbox.vue'
import UiBadge from '../ui/UiBadge.vue'
import UiEmptyState from '../ui/UiEmptyState.vue'
import IconBtn from './IconBtn.vue'
import { t } from '../../i18n/index.js'
import { useDirectoriesStore } from '../../stores/directories.js'
import { callRuby } from '../../bridge/sketchup.js'
import { formatFileSize, docIcon, pluralFiles } from '../../format.js'
import { useDragSort } from '../../composables/useDragSort.js'

const dirs = useDirectoriesStore()

const FolderIcon = Folder
const FolderIcon2 = Folder
const FolderIcon3 = Folder
const FolderOpenIcon = FolderOpen
const RefreshIcon = RefreshCw
const PlusIcon = Plus
const GripVerticalIcon = GripVertical
const ChevronUpIcon = ChevronUp
const ChevronDownIcon = ChevronDown
const XIcon = X
const ExternalLinkIcon = ExternalLink
const ImageIcon2 = ImageIcon
const LoaderIcon = Loader2
const AlertIcon = AlertTriangle

const thumbVariants = [
  { key: 'small', label: 'S', titleKey: 'dirs.thumbSmall' },
  { key: 'medium', label: 'M', titleKey: 'dirs.thumbMedium' },
  { key: 'large', label: 'L', titleKey: 'dirs.thumbLarge' },
]

function gridCls(size) {
  return { small: 'grid-cols-6', medium: 'grid-cols-5', large: 'grid-cols-4' }[size] || 'grid-cols-5'
}

// Правки карточек: изменения уже в сторе, коммитим синк спецификаций + автосейв
function commit() {
  dirs.commit()
}

function selectDirectory(index) {
  callRuby('selectDirectory', String(index))
}

function moveUp(index) {
  if (index > 0) dirs.move(index, index - 1)
}
function moveDown(index) {
  if (index < dirs.list.length - 1) dirs.move(index, index + 1)
}
function setThumbSize(d, key) {
  if (d.thumb_size !== key) {
    d.thumb_size = key
    commit()
  }
}

function badgeText(preview) {
  switch (preview.state) {
    case 'loading': return t('dirs.badgeScanning')
    case 'timeout': return t('dirs.badgeTimeout')
    case 'missing': return t('dirs.badgeMissing')
    case 'nopath':
    case 'empty': return t('dirs.badgeNoFiles')
    default: return `${preview.count} ${pluralFiles(preview.count)}`
  }
}
function badgeVariant(preview) {
  return preview.state === 'ready' && preview.count > 0 ? 'accent' : 'neutral'
}

const drag = useDragSort({
  onDrop: (from, to) => dirs.move(from, to),
})
</script>

<style scoped>
.dragging {
  opacity: 0.45;
}
</style>
