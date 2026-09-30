<template>
  <div class="tpl-single-column-layout">
    <div class="tpl-card" id="card_params">
      <div class="tpl-card-header">
        <div class="tpl-card-title-group">
          <span class="tpl-card-icon"><i class="modus-icons">tune</i></span>
          <span class="tpl-card-title">Параметры страницы</span>
        </div>
        <div class="tpl-card-header-actions">
          <label class="tpl-header-ctl" title="Размер между строками (мм) — общий отступ между параметрами и блоками на листе, один для всего шаблона">
            <span>Между строками</span>
            <select class="tpl-param-select tpl-header-linegap" :value="String(ed.lineGap)" @change="setLineGap">
              <option v-for="g in LINE_GAPS" :key="g" :value="String(g)">{{ g }} мм</option>
            </select>
          </label>
          <label class="tpl-header-ctl" title="Небольшая линия-разделитель между соседними строками параметров на листе, шириной с текст строки">
            <input type="checkbox" class="tpl-header-line" :checked="ed.lineEnabled" @change="legacy('tplEditorSetLineEnabled', $event.target.checked)">
            <span>Линия</span>
          </label>
          <button
            type="button"
            class="btn btn-xs btn-secondary"
            title="Горизонтальный блок: перетащенные в него параметры выстроятся в одну строку через « | »"
            @click="legacy('tplEditorCreateGroup', 'horizontal')"
          ><i class="modus-icons">drag_horiz</i> Блок</button>
          <button
            type="button"
            class="btn btn-xs btn-secondary"
            title="Вертикальный блок: перетащенные в него параметры выстроятся друг под другом, каждый на своей строке"
            @click="legacy('tplEditorCreateGroup', 'vertical')"
          ><i class="modus-icons">drag_vert</i> Блок</button>
          <button
            type="button"
            class="btn btn-xs btn-primary"
            @click="legacy('openParamModal', 'create', null, ed.tplKey)"
          ><i class="modus-icons">add_circle</i> Создать параметр</button>
        </div>
      </div>
      <div class="tpl-card-body">
        <p class="field-hint tpl-param-hint">Параметр создается из данных «Данные проекта», «Папки спецификации», сцены или страницы. В строке параметра задаются: размер шрифта, цвет, заголовок и место на странице — кнопка с 8 направлениями (углы и стороны листа). Шрифт и начертание наследуются из общих настроек над карточкой. «Размер между строками» и линия-разделитель «Линия» — общие для всех параметров и блоков, задаются в шапке карточки. 📦 Блок объединяет параметры: горизонтальный — в одну строку через « | », вертикальный — каждый параметр на своей строке.</p>

        <div
          class="tpl-params-list template-settings-scroll"
          id="templateSettingsContainer"
          @dragover="onListDragOver"
        >
          <div v-if="!ed.params.length" class="tpl-params-empty">Параметров пока нет — нажмите «+ Создать параметр».</div>

          <!-- Верхнеуровневые строки: параметры и блоки -->
          <div
            v-for="p in ed.params"
            :key="p.id"
            class="tpl-param-row"
            :class="[{
              'disabled-block': !p.visible,
              'tpl-param-group': p.group,
              dragging: drag && drag.id === p.id,
              'drag-over-top': isOver('row', p.id, true),
              'drag-over-bottom': isOver('row', p.id, false),
            }]"
            :data-id="p.id"
            :data-group="p.group ? 'true' : undefined"
            :draggable="dragArm === p.id"
            @mousedown="armRow($event, p.id)"
            @mouseup="dragArm = p.id"
            @dragstart="onDragStart($event, p.id, null)"
            @dragover="onRowDragOver($event, p, p.id, null)"
            @dragleave="clearOverIf($event)"
            @drop="onRowDrop($event, p.id)"
            @dragend="clearDrag"
          >
            <div class="tpl-param-head">
              <span class="drag-handle tpl-param-drag" title="Перетащите, чтобы изменить порядок">⠿</span>
              <label class="tpl-param-vis" title="Выводить параметр на страницах шаблона">
                <input type="checkbox" class="tpl-param-visible" :checked="p.visible" @change="legacy('tplEditorSetVisible', p.id, $event.target.checked)">
                <span>Вкл</span>
              </label>
              <div class="tpl-param-main">
                <span v-if="!p.group" class="tpl-param-label">{{ p._label }}</span>
                <span v-else class="tpl-param-label"><i class="modus-icons" style="font-size: 13px; vertical-align: -1px; margin-right: 3px">{{ p.direction === 'vertical' ? 'drag_vert' : 'drag_horiz' }}</i> Блок</span>
                <span v-if="!p.group && p._shownLabel" class="tpl-param-caption">«{{ p._shownLabel }}»</span>
                <template v-if="!p.group">
                  <span v-if="p._preview" class="tpl-line-preview">({{ p._preview }})</span>
                  <span v-else class="tpl-line-preview tpl-param-preview-empty">(нет данных)</span>
                </template>
                <input
                  v-if="p.group"
                  v-model="p.label"
                  type="text"
                  class="form-control tpl-param-group-label"
                  placeholder="Название блока (необязательно)"
                  @input="legacy('tplEditorUpdate', p.id, { label: p.label }, false)"
                >
                <span v-if="p.group" class="tpl-param-count">{{ countText(p._children.length) }}</span>
              </div>
              <div class="tpl-param-actions">
                <button type="button" class="tpl-param-btn tpl-param-up" title="Выше в списке" @click="legacy('tplEditorMove', p.id, -1)">▲</button>
                <button type="button" class="tpl-param-btn tpl-param-down" title="Ниже в списке" @click="legacy('tplEditorMove', p.id, 1)">▼</button>
                <button
                  v-if="!p.group"
                  type="button"
                  class="tpl-param-btn tpl-param-edit"
                  title="Изменить источник и заголовок"
                  @click="legacy('openParamModal', 'edit', p.id, ed.tplKey)"
                ><i class="modus-icons" style="font-size: 13px">edit</i></button>
                <button
                  type="button"
                  class="tpl-param-btn tpl-param-del"
                  :title="p.group ? 'Удалить блок вместе с его параметрами' : 'Удалить параметр'"
                  @click="legacy('tplEditorDeleteRow', p.id)"
                ><i class="modus-icons" style="font-size: 13px">delete</i></button>
              </div>
            </div>
            <div class="tpl-param-controls">
              <input
                type="color"
                class="tpl-param-color"
                :value="p.color"
                title="Цвет текста параметра"
                @input="legacy('tplEditorUpdate', p.id, { color: $event.target.value }, false)"
                @change="legacy('tplEditorUpdate', p.id, { color: $event.target.value }, true)"
              >
              <div class="tpl-param-box" title="Размер шрифта (пт)">
                <select class="tpl-param-select tpl-param-size" :value="String(p.font_size)" @change="setSize(p, $event)">
                  <option v-for="s in sizesFor(p.font_size)" :key="s" :value="String(s)">{{ s }} pt</option>
                </select>
              </div>
              <button
                type="button"
                class="tpl-param-btn tpl-param-align9"
                :class="{ active: alignPop && alignPop.rowId === p.id }"
                :title="`Место на странице: ${alignTitle(p.align, p.valign)}`"
                @click.stop="toggleAlignPop(p.id, $event)"
              >{{ alignGlyph(p.align, p.valign) }}</button>
              <label class="tpl-param-vis" title="Выводить заголовок на отдельной строке над значением на листе">
                <input type="checkbox" class="tpl-param-show-label" :checked="p.show_label" @change="legacy('tplEditorUpdate', p.id, { show_label: $event.target.checked }, true)">
                <span>Заголовок</span>
              </label>
              <span class="tpl-param-zone" title="Зона размещения параметра на странице">{{ p._zone }}</span>
            </div>

            <!-- Дети блока: одна строка через « | » -->
            <div
              v-if="p.group"
              class="tpl-param-group-list"
              :class="{ 'drag-over-group': overGroup === p.id }"
              @dragover="onGroupDragOver($event, p.id)"
              @dragleave="overGroup = null"
              @drop="onGroupDrop($event, p.id)"
            >
              <div
                v-for="c in p._children"
                :key="c.id"
                class="tpl-param-child"
                :class="{
                  dragging: drag && drag.id === c.id,
                  'drag-over-top': isOver('child', c.id, true),
                  'drag-over-bottom': isOver('child', c.id, false),
                }"
                :data-id="c.id"
                :draggable="dragArm === c.id"
                @mousedown="armRow($event, c.id)"
                @mouseup="dragArm = c.id"
                @dragstart="onDragStart($event, c.id, p.id)"
                @dragover.stop="onChildDragOver($event, c, p.id)"
                @dragleave.stop="clearOverIf($event)"
                @drop.stop="onChildDrop($event, c.id, p.id)"
                @dragend="clearDrag"
              >
                <span class="drag-handle tpl-param-drag" title="Перетащите, чтобы изменить порядок в блоке">⠿</span>
                <span class="tpl-param-child-label">{{ c._label }}</span>
                <span v-if="c._shownLabel" class="tpl-param-caption">«{{ c._shownLabel }}»</span>
                <span v-if="c._preview" class="tpl-line-preview">({{ c._preview }})</span>
                <span v-else class="tpl-line-preview tpl-param-preview-empty">(нет данных)</span>
                <label class="tpl-param-vis tpl-param-child-vis" title="Выводить заголовок перед значением внутри блока">
                  <input type="checkbox" class="tpl-param-child-show-label" :checked="c.show_label" @change="legacy('tplEditorChildShowLabel', p.id, c.id, $event.target.checked)">
                  <span>Заголовок</span>
                </label>
                <button type="button" class="tpl-param-child-out" title="Вывести из блока" @click="legacy('tplEditorChildOut', p.id, c.id)">
                  <i class="modus-icons icon-close-cross" style="font-size: 11px">content_close</i>
                </button>
              </div>
              <div v-if="!p._children.length" class="tpl-param-drop-empty">Перетащите сюда параметры — они выстроятся в одну строку через « | »</div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Поповер выравнивания: 3×3 направления, центр не используется -->
    <Teleport to="body">
      <div
        v-if="alignPop"
        ref="alignPopEl"
        class="scene-align-pop"
        :style="alignPopStyle"
        @click.stop
      >
        <template v-for="[h, v] in ALIGN_GRID" :key="h + '|' + v">
          <span v-if="h === 'center' && v === 'center'" class="scene-align-opt tpl-align-empty"></span>
          <button
            v-else
            type="button"
            class="scene-align-opt"
            :class="{ active: alignPopRow && alignPopRow.align === h && alignPopRow.valign === v }"
            :title="alignTitle(h, v)"
            @click.stop="pickAlign(h, v)"
          >{{ alignGlyph(h, v) }}</button>
        </template>
      </div>
    </Teleport>
  </div>
</template>

<script setup>
import { computed, nextTick, ref } from 'vue'
import { ui } from '../store.js'

// legacy пересоздаёт объект ui.tplEditor при каждом ре-синке — только computed
const ed = computed(() => ui.tplEditor)

const FONT_SIZES = [6, 7, 8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 48, 56, 64, 72]
const LINE_GAPS = [0, 1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10]

// Сетка выравнивания 3×3 как во вкладке «Страницы»: центр не предлагается,
// параметр всегда прижат к одному из 8 направлений (углы и стороны листа)
const ALIGN_GRID = [
  ['left', 'top'], ['center', 'top'], ['right', 'top'],
  ['left', 'center'], ['center', 'center'], ['right', 'center'],
  ['left', 'bottom'], ['center', 'bottom'], ['right', 'bottom'],
]
const ALIGN_GLYPHS = {
  'left|top': '↖', 'center|top': '↑', 'right|top': '↗',
  'left|center': '←', 'right|center': '→',
  'left|bottom': '↙', 'center|bottom': '↓', 'right|bottom': '↘',
}
function alignGlyph(h, v) {
  return ALIGN_GLYPHS[`${h}|${v}`] || '↖'
}
function alignTitle(h, v) {
  const H = { left: 'слева', center: 'по центру', right: 'справа' }
  const V = { top: 'вверху', center: 'в середине', bottom: 'внизу' }
  return `${H[h] || h} · ${V[v] || v}`
}

// --- Поповер выравнивания (позиционирование как в ScenesTab) ---
const alignPop = ref(null) // { rowId, x, anchorTop, anchorBottom, top, flip }
const alignPopEl = ref(null)
const alignPopStyle = ref({})

const alignPopRow = computed(() =>
  alignPop.value ? (ed.value?.params || []).find((p) => p.id === alignPop.value.rowId) : null
)

function toggleAlignPop(rowId, e) {
  if (alignPop.value && alignPop.value.rowId === rowId) {
    closeAlignPop()
    return
  }
  const rect = e.currentTarget.getBoundingClientRect()
  alignPop.value = {
    rowId,
    x: Math.round(rect.left + rect.width / 2),
    anchorTop: Math.round(rect.top),
    anchorBottom: Math.round(rect.bottom),
    flip: false,
    top: Math.round(rect.bottom + 4),
  }
  applyAlignPopStyle()
  nextTick(positionAlignPop)
}
function positionAlignPop() {
  const pop = alignPopEl.value
  const st = alignPop.value
  if (!pop || !st) return
  const spaceBelow = window.innerHeight - st.anchorBottom
  if (spaceBelow < pop.offsetHeight + 8) {
    st.flip = true
    st.top = st.anchorTop
  } else {
    st.flip = false
    st.top = st.anchorBottom + 4
  }
  applyAlignPopStyle()
  setTimeout(() => {
    document.addEventListener('click', closeAlignPop, { once: true })
    document.addEventListener('keydown', closeAlignPop, { once: true })
  }, 0)
}
function applyAlignPopStyle() {
  const st = alignPop.value
  if (!st) return
  alignPopStyle.value = {
    position: 'fixed',
    left: `${st.x}px`,
    top: `${st.top}px`,
    transform: st.flip ? 'translate(-50%, -100%)' : 'translateX(-50%)',
  }
}
function pickAlign(h, v) {
  const row = alignPopRow.value
  if (row) legacy('tplEditorUpdate', row.id, { align: h, valign: v }, true)
  closeAlignPop()
}
function closeAlignPop() {
  alignPop.value = null
  document.removeEventListener('click', closeAlignPop)
  document.removeEventListener('keydown', closeAlignPop)
}

function legacy(fn, ...args) {
  window.legacy?.[fn]?.(...args)
}

function sizesFor(current) {
  return FONT_SIZES.includes(current) ? FONT_SIZES : FONT_SIZES.concat([current]).sort((a, b) => a - b)
}
function setSize(p, e) {
  const sz = parseFloat(e.target.value)
  if (!isNaN(sz) && sz > 0) legacy('tplEditorUpdate', p.id, { font_size: sz }, false)
}
function setLineGap(e) {
  legacy('tplEditorSetLineGap', e.target.value)
}
// «N параметров» с согласованием окончаний
function countText(n) {
  const m10 = n % 10
  const m100 = n % 100
  const word = m10 === 1 && m100 !== 11 ? 'параметр'
    : m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14) ? 'параметра'
      : 'параметров'
  return `${n} ${word}`
}

// --- Drag & Drop: сортировка, перенос в блок/из блока, реордер детей ---
const dragArm = ref(null) // id строки с зажатой ручкой — включает draggable
const drag = ref(null) // { id, fromGroup }
const over = ref(null) // { kind: 'row'|'child', id, before }
const overGroup = ref(null)

function armRow(e, id) {
  dragArm.value = e.target.closest('input, select, button, label, .tpl-btn-group') ? null : id
}
function onDragStart(e, id, fromGroup) {
  drag.value = { id, fromGroup }
  e.dataTransfer.effectAllowed = 'move'
  e.dataTransfer.setData('text/plain', id)
}
function onListDragOver(e) {
  if (drag.value) e.preventDefault()
}
function isOver(kind, id, before) {
  return over.value && over.value.kind === kind && over.value.id === id && over.value.before === before
}
function clearOverIf(e) {
  if (!e.target.closest || e.target.closest('.tpl-param-row, .tpl-param-child') === e.currentTarget) {
    over.value = null
  }
}
function computeBefore(e) {
  const rect = e.currentTarget.getBoundingClientRect()
  return e.clientY < rect.top + rect.height / 2
}
function onRowDragOver(e, p, id, fromGroup) {
  if (!drag.value) return
  if (e.target.closest('.tpl-param-group-list')) return // подсветку даёт список детей
  if (e.target.closest('.tpl-param-row') !== e.currentTarget) return // событие из вложенной строки
  e.preventDefault()
  e.dataTransfer.dropEffect = 'move'
  if (drag.value.fromGroup === null && drag.value.id === id) return
  over.value = { kind: 'row', id, before: computeBefore(e) }
}
function onRowDrop(e, targetId) {
  if (e.target.closest('.tpl-param-row') !== e.currentTarget) return
  if (!drag.value) return
  e.preventDefault()
  e.stopPropagation()
  const op = {
    dragId: drag.value.id,
    fromGroup: drag.value.fromGroup,
    kind: 'row',
    targetId,
    before: over.value && over.value.id === targetId ? over.value.before : computeBefore(e),
  }
  clearDrag()
  legacy('tplEditorDrop', op)
}
function onGroupDragOver(e, groupId) {
  if (!drag.value) return
  e.preventDefault()
  e.dataTransfer.dropEffect = 'move'
  overGroup.value = groupId
}
function onGroupDrop(e, groupId) {
  e.preventDefault()
  e.stopPropagation()
  overGroup.value = null
  if (!drag.value) return
  const op = { dragId: drag.value.id, fromGroup: drag.value.fromGroup, kind: 'group', targetId: groupId }
  clearDrag()
  legacy('tplEditorDrop', op)
}
function onChildDragOver(e, c, parentGroup) {
  if (!drag.value) return
  e.preventDefault()
  e.dataTransfer.dropEffect = 'move'
  if (drag.value.fromGroup === parentGroup && drag.value.id === c.id) return
  over.value = { kind: 'child', id: c.id, before: computeBefore(e) }
}
function onChildDrop(e, childId, parentGroup) {
  if (!drag.value) return
  e.preventDefault()
  e.stopPropagation()
  const op = {
    dragId: drag.value.id,
    fromGroup: drag.value.fromGroup,
    kind: 'child',
    toGroup: parentGroup,
    targetId: childId,
    before: over.value && over.value.id === childId ? over.value.before : computeBefore(e),
  }
  clearDrag()
  legacy('tplEditorDrop', op)
}
function clearDrag() {
  drag.value = null
  dragArm.value = null
  over.value = null
  overGroup.value = null
}
</script>
