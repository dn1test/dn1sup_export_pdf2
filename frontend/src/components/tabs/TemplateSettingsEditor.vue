<template>
  <div class="flex min-h-0 flex-1 flex-col">
    <!-- Шапка карточки: общие настройки стека параметров -->
    <div class="flex flex-wrap items-center gap-x-3 gap-y-1.5 border-b border-ink-100 px-3.5 py-2">
      <div class="flex items-center gap-1.5 text-[13px] font-semibold text-ink-900">
        <SlidersIcon :size="14" class="text-ink-400" />
        {{ t('tse.title') }}
      </div>
      <div class="ml-auto flex flex-wrap items-center gap-x-3 gap-y-1.5">
        <label class="flex items-center gap-1.5 text-[11px] text-ink-500" :title="t('tse.lineGapTitle')">
          {{ t('tse.lineGapLabel') }}
          <UiSelect
            :model-value="String(templates.lineSettings.line_gap)"
            class="!h-6 !w-[70px] text-xs"
            @update:model-value="templates.setLineGap($event)"
          >
            <option v-for="g in LINE_GAPS" :key="g" :value="String(g)">{{ g }} {{ t('tpl.mmUnit') }}</option>
          </UiSelect>
        </label>
        <UiCheckbox
          :model-value="templates.lineSettings.line_enabled"
          class="text-[11px]"
          :title="t('tse.lineTitle')"
          @update:model-value="templates.setLineEnabled"
        >{{ t('tse.lineLabel') }}</UiCheckbox>
        <UiButton size="xs" :icon="ArrowLRIcon" :title="t('tse.blockHTitle')" @click="templates.createGroup('horizontal')">
          {{ t('tse.blockBtn') }}
        </UiButton>
        <UiButton size="xs" :icon="ArrowUDIcon" :title="t('tse.blockVTitle')" @click="templates.createGroup('vertical')">
          {{ t('tse.blockBtn') }}
        </UiButton>
        <UiButton size="xs" variant="primary" :icon="PlusIcon" @click="templates.openParamModal('create', null, templates.currentKey)">
          {{ t('tse.createParamBtn') }}
        </UiButton>
      </div>
    </div>

    <!-- Список параметров -->
    <div class="min-h-0 flex-1 overflow-y-auto p-3" @dragover="onListDragOver">
      <p class="mb-2 text-[11px] text-ink-400">{{ t('tse.hint') }}</p>
      <div v-if="!templates.editorView.length" class="rounded-lg border border-dashed border-ink-200 py-8 text-center text-[13px] text-ink-400">
        {{ t('tse.empty') }}
      </div>

      <div
        v-for="p in templates.editorView"
        :key="p.id"
        class="tpl-row mb-1.5 rounded-lg border transition-colors"
        :class="[
          p.group ? 'border-ink-200 bg-ink-50/60' : 'border-ink-200 bg-white',
          !p.visible && 'opacity-45',
          dndDragging?.id === p.id && 'opacity-40',
          isOver('row', p.id, true) && 'shadow-[inset_0_2px_0_0_var(--color-accent-500)]',
          isOver('row', p.id, false) && 'shadow-[inset_0_-2px_0_0_var(--color-accent-500)]',
        ]"
        :data-id="p.id"
        :draggable="dndDragArm === p.id"
        @mousedown="arm($event, p.id)"
        @mouseup="disarm()"
        @dragstart="onDragStart($event, p.id, null)"
        @dragover="onRowDragOver($event, p, p.id)"
        @dragleave="clearOverIf($event)"
        @drop="onRowDrop($event, p.id)"
        @dragend="clearDrag()"
      >
        <!-- Строка 1: вкл (после ручки), название (у блока — имя блока), порядок (ручка) и настройки отображения (заголовок, цвет, размер, выравнивание, зона) -->
        <div class="flex flex-wrap items-center gap-2 px-2 py-1.5">
          <GripVerticalIcon :size="13" class="shrink-0 cursor-grab text-ink-300" :title="t('tse.dragTitle')" />
          <UiCheckbox
            :model-value="p.visible"
            class="text-[11px]"
            :title="t('tse.visibleTitle')"
            @update:model-value="templates.setVisible(p.id, $event)"
          >{{ t('tse.visibleLabel') }}</UiCheckbox>
          <span v-if="!p.group" class="max-w-40 shrink-0 truncate text-[13px] font-medium text-ink-900" :title="p._label">{{ p._label }}</span>
          <span v-else class="flex shrink-0 items-center gap-1 text-[13px] font-medium text-ink-700">
            <component :is="p.direction === 'vertical' ? ArrowUDIcon : ArrowLRIcon" :size="12" class="text-ink-400" />
            {{ t('tse.blockLabel') }}
          </span>
          <span
            class="flex size-4 shrink-0 cursor-help items-center justify-center rounded-full bg-ink-100 text-[9px] font-bold text-ink-400 hover:bg-accent-100 hover:text-accent-600"
            :title="paramHelpTitle(p)"
          >!</span>
          <input
            v-if="p.group"
            :value="p.label"
            type="text"
            class="h-6 w-40 min-w-0 rounded border border-ink-200 bg-white px-1.5 text-xs focus:border-accent-500 focus:outline-none"
            :placeholder="t('tse.groupLabelPh')"
            @input="templates.update(p.id, { label: $event.target.value })"
          >
          <span v-if="p.group" class="shrink-0 text-[10px] text-ink-400">{{ countText(p._children.length) }}</span>
          <UiCheckbox
            :model-value="p.show_label"
            class="text-[11px]"
            :title="t('tse.showLabelTitle')"
            @update:model-value="templates.update(p.id, { show_label: $event })"
          >{{ t('tse.showLabel') }}</UiCheckbox>

          <input
            type="color"
            :value="p.color"
            class="size-6 cursor-pointer rounded border border-ink-200 bg-white p-0.5"
            :title="t('tse.colorTitle')"
            @input="templates.update(p.id, { color: $event.target.value })"
          >
          <label class="flex items-center gap-1 text-[11px] text-ink-500" :title="t('tse.sizeTitle')">
            {{ t('tse.sizeLabel') }}
            <UiSelect
              :model-value="String(p.font_size)"
              class="!h-6 !w-[64px] text-xs"
              @update:model-value="templates.update(p.id, { font_size: parseFloat($event) })"
            >
              <option v-for="s in sizesFor(p.font_size)" :key="s" :value="String(s)">{{ s }} pt</option>
            </UiSelect>
          </label>
          <button
            type="button"
            class="flex size-6 items-center justify-center rounded-md border transition-colors"
            :class="alignPop === p.id
              ? 'border-accent-400 bg-accent-50 text-accent-600'
              : 'border-ink-200 text-ink-500 hover:bg-ink-50'"
            :title="t('tse.alignTitle', { align: zoneTitle(p) })"
            @click.stop="toggleAlignPop(p.id, $event)"
          >
            <component :is="alignIcon(p)" :size="12" />
          </button>
          <span class="rounded bg-ink-100 px-1.5 py-0.5 text-[10px] text-ink-500" :title="t('tse.zoneTitle')">{{ p._zone }}</span>

          <div class="ml-auto flex shrink-0 items-center gap-0.5">
            <IconBtn v-if="!p.group" :title="t('tse.editTitle')" @click="templates.openParamModal('edit', p.id, templates.currentKey)">
              <PencilIcon :size="12" />
            </IconBtn>
            <IconBtn :title="p.group ? t('tse.deleteGroupTitle') : t('tse.deleteRowTitle')" danger @click="templates.deleteRow(p.id)">
              <TrashIcon :size="12" />
            </IconBtn>
          </div>
        </div>

        <!-- Строка 2: подпись и значение (только у параметров; у блока имя перенесено в строку 1) -->
        <div v-if="!p.group" class="flex flex-wrap items-center gap-x-2 gap-y-1 border-t border-ink-100 px-2 py-1.5">
          <span v-if="p._shownLabel" class="truncate text-[11px] text-ink-400">«{{ p._shownLabel }}»</span>
          <div class="flex min-w-0 flex-1 items-center gap-1.5">
            <span v-if="p._preview" class="truncate text-[12px] text-ink-500" style="font-family: var(--page-font-family)">{{ p._preview }}</span>
            <span v-else class="text-[11px] text-ink-300 italic">{{ t('tse.noData') }}</span>
          </div>
        </div>

        <!-- Дети блока -->
        <div
          v-if="p.group"
          class="tpl-group-list mx-2 mb-2 rounded-md border transition-colors"
          :class="overGroup === p.id ? 'border-accent-400 bg-accent-50/50' : 'border-ink-200 bg-white'"
          @dragover="onGroupDragOver($event, p.id)"
          @dragleave="overGroup = null"
          @drop="onGroupDrop($event, p.id)"
        >
          <div
            v-for="c in p._children"
            :key="c.id"
            class="tpl-child flex items-center gap-1.5 border-b border-ink-100 px-2 py-1 last:border-b-0"
            :class="[
              dndDragging?.id === c.id && 'opacity-40',
              isOver('child', c.id, true) && 'shadow-[inset_0_2px_0_0_var(--color-accent-500)]',
              isOver('child', c.id, false) && 'shadow-[inset_0_-2px_0_0_var(--color-accent-500)]',
            ]"
            :data-id="c.id"
            :draggable="dndDragArm === c.id"
            @mousedown="arm($event, c.id)"
            @mouseup="disarm()"
            @dragstart="onDragStart($event, c.id, p.id)"
            @dragover.stop="onChildDragOver($event, c, p.id)"
            @dragleave.stop="clearOverIf($event)"
            @drop.stop="onChildDrop($event, c.id, p.id)"
            @dragend="clearDrag()"
          >
            <GripVerticalIcon :size="12" class="shrink-0 cursor-grab text-ink-300" :title="t('tse.dragInGroupTitle')" />
            <span class="truncate text-xs font-medium text-ink-700">{{ c._label }}</span>
            <span
              class="flex size-3.5 shrink-0 cursor-help items-center justify-center rounded-full bg-ink-100 text-[8px] font-bold text-ink-400 hover:bg-accent-100 hover:text-accent-600"
              :title="paramHelpTitle(c)"
            >!</span>
            <span v-if="c._shownLabel" class="truncate text-[10px] text-ink-400">«{{ c._shownLabel }}»</span>
            <span v-if="c._preview" class="truncate text-[11px] text-ink-500" style="font-family: var(--page-font-family)">{{ c._preview }}</span>
            <span v-else class="text-[10px] text-ink-300 italic">{{ t('tse.noData') }}</span>
            <div class="ml-auto flex shrink-0 items-center gap-1.5">
              <UiCheckbox
                :model-value="c.show_label"
                class="text-[10px]"
                :title="t('tse.childShowLabelTitle')"
                @update:model-value="templates.childShowLabel(p.id, c.id, $event)"
              >{{ t('tse.showLabel') }}</UiCheckbox>
              <IconBtn :title="t('tse.childOutTitle')" @click="templates.childOut(p.id, c.id)">
                <XIcon :size="11" />
              </IconBtn>
            </div>
          </div>
          <div v-if="!p._children.length" class="px-2 py-2 text-center text-[11px] text-ink-300">{{ t('tse.groupDropEmpty') }}</div>
        </div>
      </div>
    </div>

    <!-- Поповер выравнивания 3×3 (центр не используется) -->
    <UiPopover :open="!!alignPop" :anchor="alignPopAnchor" @close="alignPop = null">
      <AlignGrid
        :h="alignPopRow?.align || 'left'"
        :v="alignPopRow?.valign || 'top'"
        exclude-center
        @pick="pickAlign"
      />
    </UiPopover>
  </div>
</template>

<script setup>
import { computed, ref } from 'vue'
import {
  SlidersHorizontal, GripVertical, Plus, Pencil, Trash, X,
  ArrowLeftRight, ArrowUpDown,
  ArrowUpLeft, ArrowUp, ArrowUpRight, ArrowLeft, Circle, ArrowRight,
  ArrowDownLeft, ArrowDown, ArrowDownRight,
} from '@lucide/vue'
import UiButton from '../ui/UiButton.vue'
import UiCheckbox from '../ui/UiCheckbox.vue'
import UiSelect from '../ui/UiSelect.vue'
import UiPopover from '../ui/UiPopover.vue'
import AlignGrid from '../ui/AlignGrid.vue'
import IconBtn from './IconBtn.vue'
import { paramHelpTitle } from '../paramHelp.js'
import { t, locale } from '../../i18n/index.js'
import { useTemplatesStore } from '../../stores/templates.js'

const templates = useTemplatesStore()

const LINE_GAPS = [0, 1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10]
const FONT_SIZES = [6, 7, 8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 48, 56, 64, 72]

const SlidersIcon = SlidersHorizontal
const GripVerticalIcon = GripVertical
const PlusIcon = Plus
const PencilIcon = Pencil
const TrashIcon = Trash
const XIcon = X
const ArrowLRIcon = ArrowLeftRight
const ArrowUDIcon = ArrowUpDown

const ALIGN_ICONS = {
  'left|top': ArrowUpLeft, 'center|top': ArrowUp, 'right|top': ArrowUpRight,
  'left|center': ArrowLeft, 'center|center': Circle, 'right|center': ArrowRight,
  'left|bottom': ArrowDownLeft, 'center|bottom': ArrowDown, 'right|bottom': ArrowDownRight,
}
function alignIcon(p) {
  return ALIGN_ICONS[`${p.align}|${p.valign}`] || ArrowUpLeft
}
function zoneTitle(p) {
  const H = { left: t('tse.alignH.left'), center: t('tse.alignH.center'), right: t('tse.alignH.right') }
  const V = { top: t('tse.alignV.top'), center: t('tse.alignV.center'), bottom: t('tse.alignV.bottom') }
  return `${H[p.align] || p.align} · ${V[p.valign] || p.valign}`
}

function sizesFor(current) {
  return FONT_SIZES.includes(current) ? FONT_SIZES : FONT_SIZES.concat([current]).sort((a, b) => a - b)
}

// «N параметров» с согласованием окончаний
function countText(n) {
  if (locale.value === 'en') return n === 1 ? t('tse.countOne', { n }) : t('tse.countMany', { n })
  const m10 = n % 10
  const m100 = n % 100
  const key = (m10 === 1 && m100 !== 11) ? 'tse.countOne'
    : (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) ? 'tse.countFew'
      : 'tse.countMany'
  return t(key, { n })
}

// --- Поповер выравнивания ---
const alignPop = ref(null)
const alignPopAnchor = ref(null)

const alignPopRow = computed(() =>
  alignPop.value ? templates.editorView.find((p) => p.id === alignPop.value) : null,
)

function toggleAlignPop(rowId, e) {
  if (alignPop.value === rowId) {
    alignPop.value = null
    return
  }
  alignPopAnchor.value = e.currentTarget
  alignPop.value = rowId
}
function pickAlign(h, v) {
  if (alignPopRow.value) templates.update(alignPopRow.value.id, { align: h, valign: v })
  alignPop.value = null
}

// --- Drag & Drop: сортировка, перенос в блок/из блока, реордер детей ---
const dndDragArm = ref(null) // id строки с зажатой ручкой — включает draggable
const dndDragging = ref(null) // { id, fromGroup }
const over = ref(null) // { kind: 'row'|'child', id, before }
const overGroup = ref(null)

function arm(e, id) {
  dndDragArm.value = e.target.closest('input, select, button, label, a, textarea') ? null : id
}
function disarm() {
  dndDragArm.value = null
}
function clearDrag() {
  dndDragging.value = null
  dndDragArm.value = null
  over.value = null
  overGroup.value = null
}

function onDragStart(e, id, fromGroup) {
  dndDragging.value = { id, fromGroup }
  e.dataTransfer.effectAllowed = 'move'
  e.dataTransfer.setData('text/plain', id)
}
function onListDragOver(e) {
  if (dndDragging.value) e.preventDefault()
}
function isOver(kind, id, before) {
  const o = over.value
  return !!o && o.kind === kind && o.id === id && o.before === before
}
function clearOverIf(e) {
  // сброс подсветки, когда курсор реально покидает строку (не уходит на ребёнка)
  if (!e.relatedTarget || !e.currentTarget.contains(e.relatedTarget)) over.value = null
}
function computeBefore(e) {
  const rect = e.currentTarget.getBoundingClientRect()
  return e.clientY < rect.top + rect.height / 2
}
function onRowDragOver(e, p, id) {
  if (!dndDragging.value) return
  if (e.target.closest('.tpl-group-list')) return // подсветку даёт список детей
  if (e.target.closest('.tpl-row') !== e.currentTarget) return // событие из вложенной строки
  e.preventDefault()
  e.dataTransfer.dropEffect = 'move'
  if (dndDragging.value.fromGroup === null && dndDragging.value.id === id) return
  over.value = { kind: 'row', id, before: computeBefore(e) }
}
function onRowDrop(e, targetId) {
  if (e.target.closest('.tpl-row') !== e.currentTarget) return
  if (!dndDragging.value) return
  e.preventDefault()
  e.stopPropagation()
  const op = {
    dragId: dndDragging.value.id,
    fromGroup: dndDragging.value.fromGroup,
    kind: 'row',
    targetId,
    before: over.value && over.value.id === targetId ? over.value.before : computeBefore(e),
  }
  clearDrag()
  templates.drop(op)
}
function onGroupDragOver(e, groupId) {
  if (!dndDragging.value) return
  e.preventDefault()
  e.dataTransfer.dropEffect = 'move'
  overGroup.value = groupId
}
function onGroupDrop(e, groupId) {
  e.preventDefault()
  e.stopPropagation()
  overGroup.value = null
  if (!dndDragging.value) return
  const op = { dragId: dndDragging.value.id, fromGroup: dndDragging.value.fromGroup, kind: 'group', targetId: groupId }
  clearDrag()
  templates.drop(op)
}
function onChildDragOver(e, c, parentGroup) {
  if (!dndDragging.value) return
  e.preventDefault()
  e.dataTransfer.dropEffect = 'move'
  if (dndDragging.value.fromGroup === parentGroup && dndDragging.value.id === c.id) return
  over.value = { kind: 'child', id: c.id, before: computeBefore(e) }
}
function onChildDrop(e, childId, parentGroup) {
  if (!dndDragging.value) return
  e.preventDefault()
  e.stopPropagation()
  const op = {
    dragId: dndDragging.value.id,
    fromGroup: dndDragging.value.fromGroup,
    kind: 'child',
    toGroup: parentGroup,
    targetId: childId,
    before: over.value && over.value.id === childId ? over.value.before : computeBefore(e),
  }
  clearDrag()
  templates.drop(op)
}
</script>
