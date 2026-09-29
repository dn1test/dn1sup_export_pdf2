<template>
  <div class="scenes-panel" id="scenesPanel">
    <div class="scenes-toolbar">
      <div class="scenes-quick-actions">
        <button class="btn btn-xs btn-secondary" id="btnSelectAllScenes" title="Выбрать все сцены"><i class="modus-icons">check_mark</i> Все</button>
        <button class="btn btn-xs btn-secondary" id="btnDeselectAllScenes" title="Снять выбор"><i class="modus-icons">content_close</i> Снять</button>
        <button class="btn btn-xs btn-secondary" id="btnRefreshThumbs" title="Перерисовать мини-превью заново: SketchUp по очереди переключится на каждую страницу, снимет свежий эскиз и вернётся на текущую страницу">
          <i class="modus-icons">refresh</i> Обновить эскизы
        </button>
      </div>
      <span class="info-text">Сцены SketchUp и сопоставление с шаблонами:</span>
      <div class="scenes-quick-actions">
        <label class="checkbox-label" title="Фон сцены (небо/земля/туман) включается/выключается сразу на всех страницах и на эскизах; водяные знаки — отдельная галка">
          <input type="checkbox" id="chk_scenes_background">
          <span>Фон</span>
        </label>
        <label class="checkbox-label" title="Водяные знаки из стиля сцены SketchUp включаются/выключаются сразу на всех страницах и на эскизах — независимо от фона">
          <input type="checkbox" id="chk_scenes_watermarks">
          <span>Водяной знак</span>
        </label>
        <label class="checkbox-label" title="Рамка кадра в окне SketchUp: включить/выключить сразу на всех страницах (индивидуально — в меню кадра строки)">
          <input type="checkbox" id="chk_scenes_frame_all">
          <span>Кадр все</span>
        </label>
        <button class="btn btn-xs btn-secondary" id="btnApplyTemplateAll" title="Назначить шаблон из первой строки всем сценам сразу">
          <i class="modus-icons">layers</i> Шаблон всем
        </button>
      </div>
    </div>

    <div class="table-container">
      <table class="scenes-table" id="scenesTable">
        <thead>
          <tr>
            <th width="34" class="th-check" title="Включить в экспорт">Вкл</th>
            <th width="44" class="th-order" title="Перетащите строку мышью для изменения порядка следования">№</th>
            <th width="108" class="th-preview" title="Мини предпросмотр страницы (3:2)">Превью</th>
            <th>Сцена / Описание</th>
            <th width="92" class="th-aspect" title="Пропорции кадра, рамка и видовой экран — индивидуально для каждой страницы (меню открывается кликом)">Кадр</th>
            <th width="74" class="th-scale" title="Размещение картинки на странице, % от листа — индивидуально для каждой страницы">Масштаб</th>
            <th width="64" class="th-align" title="Выравнивание эскиза на странице — индивидуально для каждой страницы">Выравн.</th>
            <th width="120" title="Шаблон страницы, назначаемый этой сцене">Шаблон</th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="!ui.scenes.length">
            <td colspan="8" class="dir-empty-state" style="text-align: center">
              Сцены модели не загружены — откройте вкладку заново или нажмите «Обновить эскизы».
            </td>
          </tr>
          <tr
            v-for="(sc, index) in ui.scenes"
            :key="sc.uid"
            :draggable="dragArm === sc.uid"
            :class="{
              'active-split-scene': sc.item.page_type === ui.currentTemplate,
              'selected-scene-row': index === ui.selectedSceneIndex,
              dragging: dragIdx === index,
              'drag-over-top': overIdx === index && overPos === 'top',
              'drag-over-bottom': overIdx === index && overPos === 'bottom',
            }"
            @mousedown="onRowMouseDown($event, sc)"
            @mouseup="dragArm = sc.uid"
            @click="legacy('focusScene', index, true)"
            @dragstart="onDragStart($event, index)"
            @dragover="onDragOver($event, index)"
            @dragleave="clearOver"
            @drop="onDrop($event, index)"
            @dragend="clearDrag"
          >
            <!-- 1. Вкл -->
            <td class="scene-check-cell" @click.stop>
              <input
                type="checkbox"
                :checked="sc.item.enabled !== false"
                title="Включить / исключить сцену из экспорта в PDF"
                @change="toggleEnabled(sc, $event)"
              >
            </td>

            <!-- 2. № и ручка перетаскивания -->
            <td class="scene-num-cell" title="Перетащите строку мышью для изменения порядка">
              <div class="scene-num-row">
                <span class="drag-handle" title="Перетащите мышью для изменения порядка">⠿</span>
                <span class="row-num">{{ index + 1 }}</span>
              </div>
            </td>

            <!-- 3. Мини превью страницы -->
            <td class="scene-preview-cell">
              <div class="scene-mini-preview-wrap">
                <div
                  class="scene-mini-sheet"
                  :title="`Сцена ${index + 1}: ${sc.item.name || 'Сцена'}\nНажмите для перехода к этому виду в SketchUp`"
                  @click.stop="legacy('focusScene', index, true)"
                >
                  <img
                    v-if="thumbUrl(sc.item, index)"
                    :src="thumbUrl(sc.item, index)"
                    :alt="sc.item.name || 'Preview'"
                    class="mini-sheet-img"
                  >
                  <div v-else class="mini-sheet-placeholder">
                    <span class="mini-sheet-placeholder-icon">
                      <i class="modus-icons" style="font-size: 18px; color: var(--text-dim, #6a6e79)">insert_photo</i>
                    </span>
                  </div>
                </div>
              </div>
            </td>

            <!-- Сцена / Описание -->
            <td class="scene-info-cell">
              <div class="scene-info-wrap">
                <input
                  v-model="sc.item.name"
                  type="text"
                  class="table-input scene-name-input"
                  placeholder="Название сцены..."
                  title="Редактировать название сцены"
                  @click.stop
                  @focus="legacy('focusScene', index, false)"
                  @input="legacy('sceneTextChanged')"
                  @change="legacy('sceneNameCommitted', index)"
                  @keydown.enter="$event.target.blur()"
                >
                <input
                  v-model="sc.item.description"
                  type="text"
                  class="table-input scene-desc-input"
                  placeholder="Описание на листе..."
                  title="Описание / примечание на листе"
                  @click.stop
                  @focus="legacy('focusScene', index, false)"
                  @input="legacy('sceneTextChanged')"
                  @change="legacy('sceneDescCommitted', index)"
                  @keydown.enter="$event.target.blur()"
                >
              </div>
            </td>

            <!-- 4. Кадр: пропорции (попап) + рамка -->
            <td class="scene-aspect-cell">
              <div class="scene-frame-ctrl">
                <button
                  type="button"
                  class="scene-frame-btn"
                  :class="{ 'frame-on': sc.item.frame_overlay === true }"
                  title="Пропорции кадра для этой страницы"
                  @click.stop="togglePopover('ratio', index, $event)"
                  @focus="legacy('focusScene', index, false)"
                >
                  <span class="scene-frame-ratio">{{ ratioLabel(normRatio(sc.item)) }}</span>
                  <span class="scene-frame-dot"></span>
                  <i class="modus-icons scene-frame-caret">expand_more</i>
                </button>
                <input
                  type="checkbox"
                  class="scene-frame-check"
                  :checked="sc.item.frame_overlay === true"
                  title="Рамка кадра для этой страницы (вкл/выкл)"
                  @click.stop
                  @change="toggleFrame(sc, index, $event)"
                >
              </div>
            </td>

            <!-- 5. Масштаб -->
            <td class="scene-scale-cell">
              <select
                class="table-select scene-scale-select"
                title="Размещение картинки на странице (% от листа)"
                :value="normScale(sc.item)"
                @click.stop
                @focus="legacy('focusScene', index, false)"
                @change="setScale(sc, index, $event)"
              >
                <option v-for="pct in [60, 70, 80, 90, 100]" :key="pct" :value="String(pct)">{{ pct }}%</option>
              </select>
            </td>

            <!-- 6. Выравнивание (попап 3×3) -->
            <td class="scene-align-cell">
              <button
                type="button"
                class="scene-align-btn"
                :title="`Выравнивание эскиза: ${alignTitle(normAlignH(sc.item), normAlignV(sc.item))}`"
                @click.stop="togglePopover('align', index, $event)"
              >{{ alignGlyph(normAlignH(sc.item), normAlignV(sc.item)) }}</button>
            </td>

            <!-- 7. Шаблон страницы -->
            <td class="scene-type-cell">
              <div class="scene-template-cell-wrap">
                <select
                  v-model="sc.item.page_type"
                  class="table-select"
                  :title="typeDescription(sc.item)"
                  @click.stop
                  @focus="legacy('focusScene', index, false)"
                  @change="legacy('scenePageTypeChanged', index, sc.item.page_type)"
                >
                  <option v-for="t in optionsFor(sc.item)" :key="t.key" :value="t.key">{{ t.name }}</option>
                </select>
                <button
                  type="button"
                  class="btn-goto-template"
                  title="Перейти к настройке этого шаблона страницы"
                  @click.stop="legacy('gotoTemplateEditor', index)"
                >
                  <i class="modus-icons" style="font-size: 13px">settings</i>
                </button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Попап кадра: пропорции -->
    <Teleport to="body">
      <div
        v-if="popover && popover.kind === 'ratio'"
        ref="popEl"
        class="scene-frame-pop"
        :style="popStyle"
        @click.stop
      >
        <div class="scene-frame-pop-title">Пропорции кадра</div>
        <div class="scene-frame-ratio-grid">
          <button
            v-for="[val, label] in ASPECT_OPTIONS"
            :key="val"
            type="button"
            class="scene-frame-ratio-opt"
            :class="{ active: val === normRatio(ui.scenes[popover.index]?.item) }"
            :title="`Пропорции кадра ${label}`"
            @click.stop="pickRatio(val)"
          >{{ label }}</button>
        </div>
      </div>
      <div
        v-if="popover && popover.kind === 'align'"
        ref="popEl"
        class="scene-align-pop"
        :style="popStyle"
        @click.stop
      >
        <button
          v-for="[h, v] in ALIGN_GRID"
          :key="h + '|' + v"
          type="button"
          class="scene-align-opt"
          :class="{ active: h === normAlignH(ui.scenes[popover.index]?.item) && v === normAlignV(ui.scenes[popover.index]?.item) }"
          :title="alignTitle(h, v)"
          @click.stop="pickAlign(h, v)"
        >{{ alignGlyph(h, v) }}</button>
      </div>
    </Teleport>
  </div>
</template>

<script setup>
import { nextTick, ref } from 'vue'
import { ui } from '../store.js'
const ASPECT_OPTIONS = [['3:2', '3:2'], ['4:3', '4:3'], ['5:4', '5:4'], ['16:9', '16:9'], ['1:1', '1:1'], ['4:5', '4:5'], ['page', 'По листу']]
const ALIGN_GRID = [
  ['left', 'top'], ['center', 'top'], ['right', 'top'],
  ['left', 'center'], ['center', 'center'], ['right', 'center'],
  ['left', 'bottom'], ['center', 'bottom'], ['right', 'bottom'],
]
const ALIGN_GLYPHS = {
  'left|top': '↖', 'center|top': '↑', 'right|top': '↗',
  'left|center': '←', 'center|center': '•', 'right|center': '→',
  'left|bottom': '↙', 'center|bottom': '↓', 'right|bottom': '↘',
}

function legacy(fn, ...args) {
  window.legacy?.[fn]?.(...args)
}

function normRatio(item) {
  const cur = (item.aspect_ratio || '4:3').trim()
  return ASPECT_OPTIONS.some(([val]) => val === cur) ? cur : '4:3'
}
function ratioLabel(val) {
  return String(val).toLowerCase() === 'page' ? 'По листу' : val
}
function normAlignH(item) {
  return ['left', 'center', 'right'].includes(item.align_h) ? item.align_h : 'center'
}
function normAlignV(item) {
  return ['top', 'center', 'bottom'].includes(item.align_v) ? item.align_v : 'center'
}
function alignGlyph(h, v) {
  return ALIGN_GLYPHS[`${h}|${v}`] || '•'
}
function alignTitle(h, v) {
  const H = { left: 'по левому краю', center: 'по центру', right: 'по правому краю' }
  const V = { top: 'по верху', center: 'по центру', bottom: 'по низу' }
  if (h === 'center' && v === 'center') return 'по центру страницы'
  if (v === 'center') return `по горизонтали ${H[h] || h}`
  if (h === 'center') return `по вертикали ${V[v] || v}`
  return `${H[h] || h} · ${V[v] || v}`
}
function normScale(item) {
  return String(parseInt(item.scale_pct, 10) || 100)
}
function thumbUrl(item, index) {
  const key = item.name || item.original_name || ''
  return item.thumbnail || ui.sceneThumbnails[key] || ui.sceneThumbnails[item.original_name] || ui.sceneThumbnails[index]
}
function optionsFor(item) {
  const opts = ui.templateOptions
  if (item.page_type && !opts.some((t) => t.key === item.page_type)) {
    return [...opts, { key: item.page_type, name: item.page_type, description: '' }]
  }
  return opts
}
function typeDescription(item) {
  const sel = ui.templateOptions.find((t) => t.key === item.page_type)
  return sel ? sel.description : ''
}

// Мутации строк: write-through в state.scenes + legacy-синхронизация
function toggleEnabled(sc, e) {
  sc.item.enabled = e.target.checked
  legacy('sceneEnabledChanged')
}
function toggleFrame(sc, index, e) {
  sc.item.frame_overlay = e.target.checked
  legacy('sceneFrameToggled', index, e.target.checked)
}
function setScale(sc, index, e) {
  const scale = parseInt(e.target.value, 10) || 100
  sc.item.scale_pct = scale
  legacy('sceneScaleChanged', index, scale)
}
function pickRatio(val) {
  const item = ui.scenes[popover.value.index]?.item
  if (item) {
    // Пропорции — персональная настройка страницы; в блок шаблона не пишем
    item.aspect_ratio = val
    legacy('sceneRatioPicked', popover.value.index, val)
  }
  closePopover()
}
function pickAlign(h, v) {
  const item = ui.scenes[popover.value.index]?.item
  if (item) {
    item.align_h = h
    item.align_v = v
    legacy('notifyChange')
  }
  closePopover()
}

// --- Попапы (кадр / выравнивание), позиционирование как в оригинале ---
const popover = ref(null) // { kind, index, x, top, flip }
const popEl = ref(null)

function togglePopover(kind, index, e) {
  if (popover.value && popover.value.kind === kind && popover.value.index === index) {
    closePopover()
    return
  }
  legacy('focusScene', index, false)
  const rect = e.currentTarget.getBoundingClientRect()
  popover.value = {
    kind,
    index,
    x: Math.round(rect.left + rect.width / 2),
    anchorTop: Math.round(rect.top),
    anchorBottom: Math.round(rect.bottom),
    flip: false,
    top: Math.round(rect.bottom + 4),
  }
  applyPopStyle()
  nextTick(positionPopover)
}
function positionPopover() {
  const pop = popEl.value
  const st = popover.value
  if (!pop || !st) return
  const spaceBelow = window.innerHeight - st.anchorBottom
  if (spaceBelow < pop.offsetHeight + 8) {
    st.flip = true
    st.top = st.anchorTop
  } else {
    st.flip = false
    st.top = st.anchorBottom + 4
  }
  applyPopStyle()
  setTimeout(() => {
    document.addEventListener('click', closePopover, { once: true })
    document.addEventListener('keydown', closePopover, { once: true })
  }, 0)
}
const popStyle = ref({})
function applyPopStyle() {
  const st = popover.value
  if (!st) return
  popStyle.value = {
    position: 'fixed',
    left: `${st.x}px`,
    top: `${st.top}px`,
    transform: st.flip ? 'translate(-50%, -100%)' : 'translateX(-50%)',
  }
}
function closePopover() {
  popover.value = null
  document.removeEventListener('click', closePopover)
  document.removeEventListener('keydown', closePopover)
}

// --- Drag & Drop переупорядочивание строк ---
const dragArm = ref(null)
const dragIdx = ref(null)
const overIdx = ref(null)
const overPos = ref(null)

function onRowMouseDown(e, sc) {
  dragArm.value = e.target.closest('input, select, button, a') ? null : sc.uid
}
function onDragStart(e, index) {
  dragIdx.value = index
  e.dataTransfer.effectAllowed = 'move'
  e.dataTransfer.setData('text/plain', String(index))
}
function onDragOver(e, index) {
  e.preventDefault()
  e.dataTransfer.dropEffect = 'move'
  if (dragIdx.value === null || dragIdx.value === index) return
  const rect = e.currentTarget.getBoundingClientRect()
  const isTop = e.clientY - rect.top < rect.height / 2
  overIdx.value = index
  overPos.value = isTop ? 'top' : 'bottom'
}
function clearOver() {
  overIdx.value = null
  overPos.value = null
}
function clearDrag() {
  dragIdx.value = null
  dragArm.value = null
  clearOver()
}
function onDrop(e, index) {
  e.preventDefault()
  e.stopPropagation()
  if (dragIdx.value === null || dragIdx.value === index) {
    clearDrag()
    return
  }
  const rect = e.currentTarget.getBoundingClientRect()
  const isTop = e.clientY - rect.top < rect.height / 2
  let dropIndex = isTop ? index : index + 1
  if (dragIdx.value < dropIndex) dropIndex -= 1
  if (dropIndex !== dragIdx.value) {
    const [moved] = ui.scenes.splice(dragIdx.value, 1)
    ui.scenes.splice(dropIndex, 0, moved)
    legacy('commitScenesReorder', dragIdx.value, dropIndex)
  }
  clearDrag()
}
</script>
