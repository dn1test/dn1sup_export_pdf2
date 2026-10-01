<template>
  <div class="flex h-full min-h-0 flex-col bg-white">
    <!-- Тулбар -->
    <div class="flex shrink-0 flex-wrap items-center gap-x-3 gap-y-1.5 border-b border-ink-200 px-3.5 py-2">
      <UiButton size="xs" :icon="CheckIcon" :title="t('scenes.selectAllTitle')" @click="scenes.setAllEnabled(true)">
        {{ t('scenes.selectAllBtn') }}
      </UiButton>
      <UiButton size="xs" :icon="XIcon" :title="t('scenes.deselectTitle')" @click="scenes.setAllEnabled(false)">
        {{ t('scenes.deselectBtn') }}
      </UiButton>
      <UiButton size="xs" :icon="RefreshIcon" :title="t('scenes.refreshThumbsTitle')" @click="refreshThumbs">
        {{ t('scenes.refreshThumbsBtn') }}
      </UiButton>

      <div class="mx-1 h-5 w-px bg-ink-200" />

      <UiCheckbox
        :model-value="scenes.backgroundAll"
        :title="t('scenes.backgroundTitle')"
        @update:model-value="scenes.backgroundAllChanged"
      >{{ t('scenes.backgroundLabel') }}</UiCheckbox>
      <UiCheckbox
        :model-value="scenes.watermarksAll"
        :title="t('scenes.watermarkTitle')"
        @update:model-value="scenes.watermarksAllChanged"
      >{{ t('scenes.watermarkLabel') }}</UiCheckbox>
      <UiCheckbox
        :model-value="scenes.frameAll"
        :title="t('scenes.frameAllTitle')"
        @update:model-value="scenes.frameAllChanged"
      >{{ t('scenes.frameAllLabel') }}</UiCheckbox>

      <span class="ml-auto hidden text-[11px] text-ink-400 lg:block">{{ t('scenes.infoText') }}</span>

      <UiButton size="xs" :icon="LayersIcon" :title="t('scenes.applyTemplateTitle')" @click="scenes.applyTemplateToAll()">
        {{ t('scenes.applyTemplateBtn') }}
      </UiButton>
    </div>

    <!-- Таблица -->
    <div class="min-h-0 flex-1 overflow-auto">
      <table class="w-full border-separate border-spacing-0 text-[13px]">
        <thead class="sticky top-0 z-10 bg-ink-50">
          <tr class="text-left text-[11px] font-medium tracking-wide text-ink-400 uppercase">
            <th class="w-9 border-b border-ink-200 px-2 py-1.5 text-center" :title="t('scenes.thOnTitle')">{{ t('scenes.thOn') }}</th>
            <th class="w-10 border-b border-ink-200 px-1 py-1.5" :title="t('scenes.thOrderTitle')">{{ t('scenes.thOrder') }}</th>
            <th class="w-[104px] border-b border-ink-200 px-2 py-1.5" :title="t('scenes.thPreviewTitle')">{{ t('scenes.thPreview') }}</th>
            <th class="border-b border-ink-200 px-2 py-1.5">{{ t('scenes.thSceneDesc') }}</th>
            <th class="w-[100px] border-b border-ink-200 px-2 py-1.5" :title="t('scenes.thFrameTitle')">{{ t('scenes.thFrame') }}</th>
            <th class="w-[74px] border-b border-ink-200 px-2 py-1.5" :title="t('scenes.thScaleTitle')">{{ t('scenes.thScale') }}</th>
            <th class="w-[54px] border-b border-ink-200 px-2 py-1.5 text-center" :title="t('scenes.thAlignTitle')">{{ t('scenes.thAlign') }}</th>
            <th class="w-[172px] border-b border-ink-200 px-2 py-1.5" :title="t('scenes.thTemplateTitle')">{{ t('scenes.thTemplate') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="!scenes.scenes.length">
            <td colspan="8" class="px-4 py-10 text-center text-[13px] text-ink-400">{{ t('scenes.empty') }}</td>
          </tr>
          <tr
            v-for="(sc, index) in scenes.scenes"
            :key="index + '-' + (sc.name || '') + '-' + (sc.original_name || '')"
            class="group transition-colors"
            :class="[
              drag.rowClasses(index),
              index === scenes.selectedSceneIndex ? 'bg-accent-50/70' : 'hover:bg-ink-50',
              sc.page_type === templates.currentKey ? 'shadow-[inset_2px_0_0_0_var(--color-accent-500)]' : '',
            ]"
            :draggable="drag.dragArm.value === index"
            @mousedown="drag.arm($event, index)"
            @mouseup="drag.disarm()"
            @click="scenes.focusScene(index, true)"
            @dragstart="drag.onDragStart($event, index)"
            @dragover="drag.onDragOver($event, index)"
            @dragleave="drag.clearOver()"
            @drop="drag.onDrop($event, index)"
            @dragend="drag.clearDrag()"
          >
            <!-- Вкл -->
            <td class="border-b border-ink-100 px-2 py-1 text-center" @click.stop>
              <input
                type="checkbox"
                class="size-3.5 accent-accent-600"
                :checked="sc.enabled !== false"
                :title="t('scenes.rowCheckTitle')"
                @change="scenes.setEnabled(index, $event.target.checked)"
              >
            </td>

            <!-- № и ручка -->
            <td class="border-b border-ink-100 px-1 py-1">
              <div class="flex items-center gap-0.5">
                <GripVerticalIcon :size="12" class="cursor-grab text-ink-300 opacity-40 group-hover:opacity-100" :title="t('scenes.dragTitle')" />
                <span class="font-mono text-[11px] text-ink-400" :title="t('scenes.numTitle')">{{ index + 1 }}</span>
              </div>
            </td>

            <!-- Мини-превью -->
            <td class="border-b border-ink-100 px-2 py-1">
              <div
                class="aspect-[3/2] w-full cursor-pointer overflow-hidden rounded border border-ink-200 bg-ink-50"
                :title="t('scenes.miniTitle', { n: index + 1, name: sc.name || t('scenes.sceneWord') })"
                @click.stop="scenes.focusScene(index, true)"
              >
                <img
                  v-if="scenes.thumbUrl(sc, index)"
                  :src="scenes.thumbUrl(sc, index)"
                  :alt="sc.name || 'Preview'"
                  class="h-full w-full object-cover"
                >
                <div v-else class="flex h-full w-full items-center justify-center text-ink-300">
                  <ImageIcon :size="16" class="animate-pulse" />
                </div>
              </div>
            </td>

            <!-- Название / Описание -->
            <td class="border-b border-ink-100 px-2 py-1">
              <div class="flex flex-col gap-1">
                <input
                  v-model="sc.name"
                  type="text"
                  class="h-7 w-full min-w-0 rounded border border-transparent bg-transparent px-1.5 text-[13px] font-medium text-ink-900 hover:border-ink-200 focus:border-accent-500 focus:bg-white focus:outline-none"
                  :placeholder="t('scenes.namePh')"
                  :title="t('scenes.nameTitle')"
                  @click.stop
                  @focus="scenes.selectedSceneIndex = index"
                  @change="scenes.nameCommitted(index)"
                  @keydown.enter="$event.target.blur()"
                >
                <input
                  v-model="sc.description"
                  type="text"
                  class="h-7 w-full min-w-0 rounded border border-transparent bg-transparent px-1.5 text-xs text-ink-500 hover:border-ink-200 focus:border-accent-500 focus:bg-white focus:outline-none"
                  :placeholder="t('scenes.descPh')"
                  :title="t('scenes.descTitle')"
                  @click.stop
                  @focus="scenes.selectedSceneIndex = index"
                  @change="scenes.descCommitted(index)"
                  @keydown.enter="$event.target.blur()"
                >
              </div>
            </td>

            <!-- Кадр: пропорции + рамка -->
            <td class="border-b border-ink-100 px-2 py-1">
              <div class="flex items-center gap-1.5">
                <button
                  type="button"
                  class="flex h-7 items-center gap-1 rounded-md border px-1.5 text-[11px] font-medium transition-colors"
                  :class="sc.frame_overlay === true
                    ? 'border-accent-300 bg-accent-50 text-accent-700'
                    : 'border-ink-200 bg-white text-ink-600 hover:border-ink-300'"
                  :title="t('scenes.frameBtnTitle')"
                  @click.stop="togglePop('ratio', index, $event)"
                >
                  {{ ratioLabel(sc) }}
                  <ChevronDownIcon :size="11" class="opacity-50" />
                </button>
                <input
                  type="checkbox"
                  class="size-3.5 accent-accent-600"
                  :checked="sc.frame_overlay === true"
                  :title="t('scenes.frameCheckTitle')"
                  @click.stop
                  @change="scenes.frameToggled(index, $event.target.checked)"
                >
              </div>
            </td>

            <!-- Масштаб -->
            <td class="border-b border-ink-100 px-2 py-1">
              <UiSelect
                :model-value="normScale(sc)"
                class="!h-7 text-xs"
                :title="t('scenes.scaleTitle')"
                @click.stop
                @update:model-value="scenes.scaleChanged(index, parseInt($event, 10) || 100)"
              >
                <option v-for="pct in [60, 70, 80, 90, 100]" :key="pct" :value="String(pct)">{{ pct }}%</option>
              </UiSelect>
            </td>

            <!-- Выравнивание 3×3 -->
            <td class="border-b border-ink-100 px-2 py-1 text-center">
              <button
                type="button"
                class="flex size-7 items-center justify-center rounded-md border transition-colors"
                :class="pop && pop.kind === 'align' && pop.index === index
                  ? 'border-accent-400 bg-accent-50 text-accent-600'
                  : 'border-ink-200 text-ink-500 hover:border-ink-300 hover:bg-ink-50'"
                :title="alignBtnTitle(sc)"
                @click.stop="togglePop('align', index, $event)"
              >
                <component :is="alignIcon(sc)" :size="13" />
              </button>
            </td>

            <!-- Шаблон страницы -->
            <td class="border-b border-ink-100 px-2 py-1">
              <div class="flex items-center gap-1">
                <StarIcon
                  v-if="masterAffects(sc)"
                  :size="11"
                  class="shrink-0 text-amber-400"
                  fill="currentColor"
                  :title="t('scenes.masterBadgeTitle')"
                />
                <UiSelect
                  v-model="sc.page_type"
                  class="!h-7 min-w-0 text-xs"
                  :title="templateDesc(sc)"
                  @click.stop
                  @focus="scenes.selectedSceneIndex = index"
                  @update:model-value="scenes.pageTypeChanged(index, $event)"
                >
                  <option v-for="tpl in optionsFor(sc)" :key="tpl.key" :value="tpl.key">{{ tpl.name }}</option>
                </UiSelect>
                <button
                  type="button"
                  class="flex size-6 shrink-0 items-center justify-center rounded text-ink-300 transition-colors hover:bg-ink-100 hover:text-accent-600"
                  :title="t('scenes.templateGotoTitle')"
                  @click.stop="gotoTemplate(index)"
                >
                  <SettingsIcon :size="12" />
                </button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Поповер пропорций кадра -->
    <UiPopover :open="!!pop && pop.kind === 'ratio'" :anchor="popAnchor" @close="pop = null">
      <div class="w-44">
        <div class="mb-1.5 px-1 text-[11px] font-medium text-ink-400 uppercase">{{ t('scenes.framePopTitle') }}</div>
        <div class="grid grid-cols-4 gap-1">
          <button
            v-for="[val, label] in aspectOptions"
            :key="val"
            type="button"
            class="rounded-md border px-1.5 py-1 text-[11px] font-medium transition-colors"
            :class="val === normRatio(currentPopScene)
              ? 'border-accent-500 bg-accent-50 text-accent-700'
              : 'border-ink-200 text-ink-600 hover:bg-ink-50'"
            :title="t('scenes.ratioOptTitle', { label })"
            @click="pickRatio(val)"
          >{{ label }}</button>
        </div>
      </div>
    </UiPopover>

    <!-- Поповер выравнивания 3×3 -->
    <UiPopover :open="!!pop && pop.kind === 'align'" :anchor="popAnchor" @close="pop = null">
      <AlignGrid
        :h="normAlignH(currentPopScene)"
        :v="normAlignV(currentPopScene)"
        @pick="pickAlign"
      />
    </UiPopover>
  </div>
</template>

<script setup>
import { computed, ref } from 'vue'
import {
  Check, X, RefreshCw, Layers, GripVertical, Image as ImageIcon,
  ChevronDown, Settings, Star,
  ArrowUpLeft, ArrowUp, ArrowUpRight, ArrowLeft, Circle, ArrowRight,
  ArrowDownLeft, ArrowDown, ArrowDownRight,
} from '@lucide/vue'
import UiButton from '../ui/UiButton.vue'
import UiCheckbox from '../ui/UiCheckbox.vue'
import UiSelect from '../ui/UiSelect.vue'
import UiPopover from '../ui/UiPopover.vue'
import AlignGrid from '../ui/AlignGrid.vue'
import { t } from '../../i18n/index.js'
import { useScenesStore } from '../../stores/scenes.js'
import { useTemplatesStore } from '../../stores/templates.js'
import { useAppStore } from '../../stores/app.js'
import { useDragSort } from '../../composables/useDragSort.js'

const scenes = useScenesStore()
const templates = useTemplatesStore()
const app = useAppStore()

const CheckIcon = Check
const XIcon = X
const RefreshIcon = RefreshCw
const LayersIcon = Layers
const GripVerticalIcon = GripVertical
const ChevronDownIcon = ChevronDown
const SettingsIcon = Settings
const StarIcon = Star

const aspectOptions = computed(() => [
  ['3:2', '3:2'], ['4:3', '4:3'], ['5:4', '5:4'], ['16:9', '16:9'],
  ['1:1', '1:1'], ['4:5', '4:5'],
  ['page', t('scenes.ratioPage')],
])
const ASPECT_VALUES = ['3:2', '4:3', '5:4', '16:9', '1:1', '4:5', 'page']

const ALIGN_ICONS = {
  'left|top': ArrowUpLeft, 'center|top': ArrowUp, 'right|top': ArrowUpRight,
  'left|center': ArrowLeft, 'center|center': Circle, 'right|center': ArrowRight,
  'left|bottom': ArrowDownLeft, 'center|bottom': ArrowDown, 'right|bottom': ArrowDownRight,
}

function normRatio(item) {
  const cur = String(item?.aspect_ratio || '4:3').trim()
  return ASPECT_VALUES.includes(cur) ? cur : '4:3'
}
function ratioLabel(item) {
  const v = normRatio(item)
  return v === 'page' ? t('scenes.ratioPage') : v
}
function normAlignH(item) {
  return ['left', 'center', 'right'].includes(item?.align_h) ? item.align_h : 'center'
}
function normAlignV(item) {
  return ['top', 'center', 'bottom'].includes(item?.align_v) ? item.align_v : 'center'
}
function alignIcon(item) {
  return ALIGN_ICONS[`${normAlignH(item)}|${normAlignV(item)}`] || Circle
}
function alignBtnTitle(item) {
  const H = { left: t('scenes.alignH.left'), center: t('scenes.alignH.center'), right: t('scenes.alignH.right') }
  const V = { top: t('scenes.alignV.top'), center: t('scenes.alignV.center'), bottom: t('scenes.alignV.bottom') }
  const h = normAlignH(item)
  const v = normAlignV(item)
  if (h === 'center' && v === 'center') return t('scenes.alignCenterPage')
  if (v === 'center') return t('scenes.alignHorizontal', { h: H[h] })
  if (h === 'center') return t('scenes.alignVertical', { v: V[v] })
  return `${H[h]} · ${V[v]}`
}
function normScale(item) {
  return String(parseInt(item?.scale_pct, 10) || 100)
}

// Селект «Шаблон»: если текущий ключ удалён — держим его как опцию
function optionsFor(item) {
  const opts = templates.sceneOptions
  if (item.page_type && !opts.some((tpl) => tpl.key === item.page_type)) {
    return [...opts, { key: item.page_type, name: item.page_type, description: '' }]
  }
  return opts
}

// Мастер-шаблон затрагивает страницу: включен, страница не на самом мастере
// и не является обложкой
function masterAffects(item) {
  if (!templates.masterEnabled || !templates.masterKey || item.page_type === templates.masterKey) return false
  const opt = templates.sceneOptions.find((tpl) => tpl.key === item.page_type)
  return !(opt && opt.cover)
}
function templateDesc(item) {
  const sel = templates.sceneOptions.find((tpl) => tpl.key === item.page_type)
  return sel ? sel.description : ''
}

// --- Поповеры кадра/выравнивания ---
const pop = ref(null) // { kind, index }
const popAnchor = ref(null)

function togglePop(kind, index, e) {
  if (pop.value && pop.value.kind === kind && pop.value.index === index) {
    pop.value = null
    return
  }
  scenes.selectedSceneIndex = index
  popAnchor.value = e.currentTarget
  pop.value = { kind, index }
}
const currentPopScene = computed(() => (pop.value ? scenes.scenes[pop.value.index] : null))

function pickRatio(val) {
  if (pop.value) scenes.ratioPicked(pop.value.index, val)
  pop.value = null
}
function pickAlign(h, v) {
  if (pop.value) scenes.alignPicked(pop.value.index, h, v)
  pop.value = null
}

function refreshThumbs() {
  if (scenes.thumbsInFlight) return
  scenes.thumbsManual = true
  scenes.requestThumbnails(true)
}

function gotoTemplate(index) {
  const sc = scenes.scenes[index]
  if (!sc) return
  scenes.selectedSceneIndex = index
  templates.select(sc.page_type || templates.defaultKey)
  scenes.switchToSketchupScene(sc, index)
  app.switchTab('tab-templates')
}

// --- Drag & drop строк ---
const drag = useDragSort({ onDrop: (from, to) => scenes.commitReorder(from, to) })
</script>

<style scoped>
.drag-over-top {
  box-shadow: inset 0 2px 0 0 var(--color-accent-500);
}
.drag-over-bottom {
  box-shadow: inset 0 -2px 0 0 var(--color-accent-500);
}
.dragging {
  opacity: 0.45;
}
</style>
