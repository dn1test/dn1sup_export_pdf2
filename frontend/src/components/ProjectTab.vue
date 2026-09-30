<template>
  <div>
    <!-- Top Row: 2 Columns (1: Паспорт объекта, 2: Карточка заказчика) -->
    <div class="project-columns-row">
      <!-- Column 1: Паспорт объекта (Project) — значения читает/пишет legacy по id -->
      <div class="settings-card project-col-card">
        <div class="card-header">
          <span class="card-header-icon"><i class="modus-icons">project</i></span>
          <span class="card-header-title">Паспорт объекта (Project)</span>
        </div>
        <div class="form-grid">
          <div class="form-group full-width">
            <label for="inputFurnitureName">Изделие / Название мебели</label>
            <input type="text" id="inputFurnitureName" class="form-control" placeholder="например: Шкаф купе, Тумба, Зеркало">
          </div>

          <div class="form-group">
            <label for="inputRoomName">Комната / Помещение / Место</label>
            <input type="text" id="inputRoomName" class="form-control" placeholder="например: Прихожая, Кухня-гостиная">
          </div>

          <div class="form-group">
            <label for="inputAddress">Адрес установки объекта</label>
            <input type="text" id="inputAddress" class="form-control" placeholder="например: г. Москва, ул. Никитская, д. 12, кв. 45">
          </div>

          <div class="form-group full-width">
            <label for="inputProjectDescription">Описание проекта / задания</label>
            <textarea id="inputProjectDescription" class="form-control" rows="7" placeholder="Краткое описание задания и назначения изделия..."></textarea>
          </div>
        </div>
      </div>

      <!-- Column 2: Карточка заказчика (Customer) -->
      <div class="settings-card project-col-card">
        <div class="card-header">
          <span class="card-header-icon"><i class="modus-icons">account</i></span>
          <span class="card-header-title">Карточка заказчика (Customer)</span>
        </div>
        <div class="form-grid">
          <div class="form-group full-width">
            <label for="inputCustomerId">Идентификатор заказчика (ID)</label>
            <div class="input-action-group">
              <input type="text" id="inputCustomerId" class="form-control font-mono" placeholder="CUST-260905-142650">
              <button type="button" class="btn btn-secondary btn-action" id="btnGenerateCustomerId" title="Сгенерировать уникальный идентификатор клиента"><i class="modus-icons">autorenew</i> Создать ID</button>
            </div>
          </div>

          <div class="form-group full-width">
            <label for="inputCustomer">ФИО / Контактное лицо *</label>
            <input type="text" id="inputCustomer" class="form-control" placeholder="например: Мария Смирнова, Алексей">
          </div>

          <div class="form-group full-width" id="companyFieldGroup">
            <label for="inputCompany">Название компании (для коммерческих)</label>
            <input type="text" id="inputCompany" class="form-control" placeholder="ООО &quot;Техно-Дизайн&quot;, ТЦ &quot;Атриум&quot;">
          </div>

          <div class="form-group full-width">
            <label for="inputPhone">Номер телефона</label>
            <input type="text" id="inputPhone" class="form-control" placeholder="+7 (999) 000-00-00">
          </div>

          <div class="form-group full-width">
            <label for="inputEmail">Электронная почта (Email)</label>
            <input type="email" id="inputEmail" class="form-control" placeholder="client@example.com">
          </div>
        </div>
      </div>
    </div>

    <!-- Section 3: Ход работы и жизненный цикл (Workflow) -->
    <div class="settings-card workflow-card">
      <div class="card-header">
        <span class="card-header-icon"><i class="modus-icons">time</i></span>
        <span class="card-header-title">Ход работы и жизненный цикл (Workflow)</span>
      </div>
      <div class="workflow-split-layout">
        <!-- Левая колонка: параметры жизненного цикла -->
        <div class="workflow-left-col">
          <div class="form-grid workflow-grid">
            <div class="form-group span-2">
              <label for="inputAuthor">Автор / Ответственный конструктор</label>
              <input type="text" id="inputAuthor" class="form-control" placeholder="например: Иванов И.И.">
            </div>

            <div class="form-group span-2">
              <label for="inputPrice">Стоимость проекта (руб. / валюта)</label>
              <input type="text" id="inputPrice" class="form-control" placeholder="например: 125 000">
            </div>

            <div class="form-group span-1">
              <label for="inputStartDate">Дата начала</label>
              <input type="date" id="inputStartDate" class="form-control">
            </div>

            <div class="form-group span-1">
              <label for="inputEndDate">Дата сдачи</label>
              <input type="date" id="inputEndDate" class="form-control">
            </div>

            <div class="form-group span-2">
              <label for="inputTotalDuration">Общая длительность проекта</label>
              <input type="text" id="inputTotalDuration" class="form-control" placeholder="например: 9 дней / 45 часов">
              <span class="field-hint">Пока ведется учет времени (вкладка «Статистика»), поле заполняется автоматически: «2 ч 30 мин», «1 д 4 ч»</span>
            </div>

            <div class="form-group span-1">
              <label for="inputVersion">Вариант</label>
              <input type="number" id="inputVersion" class="form-control" min="1" value="1">
            </div>

            <div class="form-group span-1">
              <label for="inputRevision">Ревизия</label>
              <input type="number" id="inputRevision" class="form-control" min="1" value="1">
            </div>

            <div class="form-group span-2">
              <label for="inputRate">Ставка руб./час</label>
              <input type="text" id="inputRate" class="form-control">
            </div>

            <div class="form-group full-width">
              <label for="inputLastEdit">Комментарий к последней правке</label>
              <input type="text" id="inputLastEdit" class="form-control" placeholder="например: Добавлены замки, правки по люку...">
            </div>
          </div>
        </div>

        <!-- Правая колонка: стадии проекта (Vue-список) -->
        <div class="workflow-right-col">
          <div class="workflow-stadia-panel">
            <div class="workflow-stadia-header">
              <span class="workflow-stadia-icon"><i class="modus-icons">check_mark</i></span>
              <span class="workflow-stadia-title">Стадии проекта (workflow.stadia):</span>
              <button
                type="button"
                class="btn btn-xs btn-secondary btn-icon-only stadia-save-default"
                title="Сохранить текущий список стадий (без галочек) как список по умолчанию"
                @click="legacy('saveStadiaDefault')"
              >
                <i class="modus-icons">save</i>
              </button>
            </div>
            <div class="stadia-checkboxes-vertical">
              <label
                v-for="(st, idx) in ui.stadia"
                :key="st.uid"
                class="stadia-checkbox-item"
                :class="{
                  checked: st.item.status,
                  dragging: dragIdx === idx,
                  'drag-over-top': overIdx === idx && overPos === 'top',
                  'drag-over-bottom': overIdx === idx && overPos === 'bottom',
                }"
                :draggable="dragArmIdx === idx"
                @mousedown="dragArmIdx = $event.target.closest('input, button') ? null : idx"
                @mouseup="dragArmIdx = idx"
                @dragstart="onDragStart($event, idx)"
                @dragover="onDragOver($event, idx)"
                @dragleave="clearOver"
                @drop="onDrop($event, idx)"
                @dragend="clearDrag"
              >
                <input v-model="st.item.status" type="checkbox" @change="legacy('stadiaChanged')">
                <span class="stadia-name">{{ st.item.name || `Стадия ${idx + 1}` }}</span>
                <button
                  v-if="ui.stadia.length > 1"
                  type="button"
                  class="stadia-delete"
                  title="Удалить стадию"
                  @click.stop.prevent="legacy('removeStadia', idx)"
                >
                  <i class="modus-icons icon-close-cross" style="font-size: 11px">content_close</i>
                </button>
              </label>
            </div>
            <div class="stadia-add-row">
              <input
                v-model="newStadiaName"
                type="text"
                class="form-control"
                placeholder="Название новой стадии..."
                @keydown.enter.prevent="addStadia"
              >
              <button type="button" class="btn btn-xs btn-primary" title="Добавить стадию в конец списка" @click="addStadia">
                <i class="modus-icons">add_circle</i> Добавить
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { ui } from '../store.js'

function legacy(fn, ...args) {
  window.legacy?.[fn]?.(...args)
}

const newStadiaName = ref('')
function addStadia() {
  if (!newStadiaName.value.trim()) return
  legacy('addStadia', newStadiaName.value)
  newStadiaName.value = ''
}

// Drag & Drop переупорядочивание стадий
const dragArmIdx = ref(null)
const dragIdx = ref(null)
const overIdx = ref(null)
const overPos = ref(null)

function onDragStart(e, idx) {
  dragIdx.value = idx
  e.dataTransfer.effectAllowed = 'move'
  e.dataTransfer.setData('text/plain', String(idx))
}
function onDragOver(e, idx) {
  e.preventDefault()
  e.dataTransfer.dropEffect = 'move'
  if (dragIdx.value === null || dragIdx.value === idx) return
  const rect = e.currentTarget.getBoundingClientRect()
  const isTop = e.clientY - rect.top < rect.height / 2
  overIdx.value = idx
  overPos.value = isTop ? 'top' : 'bottom'
}
function clearOver() {
  overIdx.value = null
  overPos.value = null
}
function clearDrag() {
  dragIdx.value = null
  dragArmIdx.value = null
  clearOver()
}
function onDrop(e, idx) {
  e.preventDefault()
  e.stopPropagation()
  if (dragIdx.value === null || dragIdx.value === idx) {
    clearDrag()
    return
  }
  const rect = e.currentTarget.getBoundingClientRect()
  let dropIndex = e.clientY - rect.top < rect.height / 2 ? idx : idx + 1
  if (dragIdx.value < dropIndex) dropIndex -= 1
  if (dropIndex !== dragIdx.value) {
    const [item] = ui.stadia.splice(dragIdx.value, 1)
    ui.stadia.splice(dropIndex, 0, item)
    legacy('commitStadia', dragIdx.value, dropIndex)
  }
  clearDrag()
}
</script>
