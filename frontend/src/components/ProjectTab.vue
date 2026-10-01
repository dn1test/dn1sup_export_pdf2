<template>
  <div>
    <!-- Top Row: 2 Columns (1: Паспорт объекта, 2: Карточка заказчика) -->
    <div class="project-columns-row">
      <!-- Column 1: Паспорт объекта (Project) — значения читает/пишет legacy по id -->
      <div class="settings-card project-col-card">
        <div class="card-header">
          <span class="card-header-icon"><i class="modus-icons">project</i></span>
          <span class="card-header-title">{{ t('project.title') }}</span>
        </div>
        <div class="form-grid">
          <div class="form-group full-width">
            <label for="inputFurnitureName">{{ t('project.furnitureLabel') }}</label>
            <input type="text" id="inputFurnitureName" class="form-control" :placeholder="t('project.furniturePh')">
          </div>

          <div class="form-group">
            <label for="inputRoomName">{{ t('project.roomLabel') }}</label>
            <input type="text" id="inputRoomName" class="form-control" :placeholder="t('project.roomPh')">
          </div>

          <div class="form-group">
            <label for="inputAddress">{{ t('project.addressLabel') }}</label>
            <input type="text" id="inputAddress" class="form-control" :placeholder="t('project.addressPh')">
          </div>
        </div>
      </div>

      <!-- Column 2: Карточка заказчика (Customer) -->
      <div class="settings-card project-col-card">
        <div class="card-header">
          <span class="card-header-icon"><i class="modus-icons">account</i></span>
          <span class="card-header-title">{{ t('customer.title') }}</span>
        </div>
        <div class="form-grid">
          <div class="form-group">
            <label for="inputCustomer">{{ t('customer.nameLabel') }}</label>
            <input type="text" id="inputCustomer" class="form-control" :placeholder="t('customer.namePh')">
          </div>

          <div class="form-group">
            <label for="inputCustomerId">{{ t('customer.idLabel') }}</label>
            <div class="input-action-group">
              <input type="text" id="inputCustomerId" class="form-control font-mono" placeholder="CUST-260905-142650">
              <button type="button" class="btn btn-secondary btn-action btn-icon-only" id="btnGenerateCustomerId" :title="t('customer.idGenTitle')" :aria-label="t('customer.idGenAria')"><i class="modus-icons">autorenew</i></button>
            </div>
          </div>

          <div class="form-group full-width" id="companyFieldGroup">
            <label for="inputCompany">{{ t('customer.companyLabel') }}</label>
            <input type="text" id="inputCompany" class="form-control" placeholder="ООО &quot;Техно-Дизайн&quot;, ТЦ &quot;Атриум&quot;">
          </div>

          <div class="form-group">
            <label for="inputPhone">{{ t('customer.phoneLabel') }}</label>
            <input type="text" id="inputPhone" class="form-control" placeholder="+7 (999) 000-00-00">
          </div>

          <div class="form-group">
            <label for="inputEmail">{{ t('customer.emailLabel') }}</label>
            <input type="email" id="inputEmail" class="form-control" placeholder="client@example.com">
          </div>
        </div>
      </div>
    </div>

    <!-- Section 3: Ход работы и жизненный цикл (Workflow) -->
    <div class="settings-card workflow-card">
      <div class="card-header">
        <span class="card-header-icon"><i class="modus-icons">time</i></span>
        <span class="card-header-title">{{ t('workflow.title') }}</span>
      </div>
      <div class="workflow-split-layout">
        <!-- Левая колонка: параметры жизненного цикла -->
        <div class="workflow-left-col">
          <div class="form-grid workflow-grid">
            <div class="form-group span-2">
              <label for="inputAuthor">{{ t('workflow.authorLabel') }}</label>
              <input type="text" id="inputAuthor" class="form-control" :placeholder="t('workflow.authorPh')">
            </div>

            <div class="form-group span-2">
              <label for="inputPrice">{{ t('workflow.priceLabel') }}</label>
              <input type="text" id="inputPrice" class="form-control" :placeholder="t('workflow.pricePh')">
            </div>

            <div class="form-group span-1">
              <label for="inputStartDateDisplay">{{ t('workflow.startDate') }}</label>
              <div class="date-field">
                <input type="text" id="inputStartDateDisplay" class="form-control" :placeholder="t('workflow.datePh')"
                       inputmode="numeric" autocomplete="off" maxlength="10">
                <input type="date" id="inputStartDate" class="date-field-native" tabindex="-1" aria-hidden="true">
                <button type="button" class="date-field-icon" data-date-picker="inputStartDate"
                        :aria-label="t('workflow.pickDate')" :title="t('workflow.pickDate')">
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor"
                       stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <rect x="3" y="4" width="18" height="18" rx="2" ry="2"></rect>
                    <line x1="16" y1="2" x2="16" y2="6"></line>
                    <line x1="8" y1="2" x2="8" y2="6"></line>
                    <line x1="3" y1="10" x2="21" y2="10"></line>
                  </svg>
                </button>
              </div>
            </div>

            <div class="form-group span-1">
              <label for="inputEndDateDisplay">{{ t('workflow.endDate') }}</label>
              <div class="date-field">
                <input type="text" id="inputEndDateDisplay" class="form-control" :placeholder="t('workflow.datePh')"
                       inputmode="numeric" autocomplete="off" maxlength="10">
                <input type="date" id="inputEndDate" class="date-field-native" tabindex="-1" aria-hidden="true">
                <button type="button" class="date-field-icon" data-date-picker="inputEndDate"
                        :aria-label="t('workflow.pickDate')" :title="t('workflow.pickDate')">
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor"
                       stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <rect x="3" y="4" width="18" height="18" rx="2" ry="2"></rect>
                    <line x1="16" y1="2" x2="16" y2="6"></line>
                    <line x1="8" y1="2" x2="8" y2="6"></line>
                    <line x1="3" y1="10" x2="21" y2="10"></line>
                  </svg>
                </button>
              </div>
            </div>

            <div class="form-group span-2">
              <label for="inputTotalDuration">{{ t('workflow.durationLabel') }}</label>
              <input type="text" id="inputTotalDuration" class="form-control" :placeholder="t('workflow.durationPh')">
            </div>

            <div class="form-group span-1">
              <label for="inputVersion">{{ t('workflow.versionLabel') }}</label>
              <input type="number" id="inputVersion" class="form-control" min="1" value="1">
            </div>

            <div class="form-group span-1">
              <label for="inputRevision">{{ t('workflow.revisionLabel') }}</label>
              <input type="number" id="inputRevision" class="form-control" min="1" value="1">
            </div>

            <div class="form-group span-2">
              <label for="inputRate">{{ t('workflow.rateLabel') }}</label>
              <input type="text" id="inputRate" class="form-control">
            </div>

            <div class="form-group full-width">
              <label for="inputLastEdit">{{ t('workflow.lastEditLabel') }}</label>
              <input type="text" id="inputLastEdit" class="form-control" :placeholder="t('workflow.lastEditPh')">
            </div>

            <div class="form-group span-2">
              <label for="inputMaterials">{{ t('workflow.materialsLabel') }}</label>
              <textarea id="inputMaterials" class="form-control" rows="10" :placeholder="t('workflow.materialsPh')"></textarea>
            </div>

            <div class="form-group span-2">
              <label for="inputLighting">{{ t('workflow.lightingLabel') }}</label>
              <textarea id="inputLighting" class="form-control" rows="10" :placeholder="t('workflow.lightingPh')"></textarea>
            </div>
          </div>
        </div>

        <!-- Правая колонка: стадии проекта (Vue-список) -->
        <div class="workflow-right-col">
          <div class="workflow-stadia-panel">
            <div class="workflow-stadia-header">
              <span class="workflow-stadia-icon"><i class="modus-icons">check_mark</i></span>
              <span class="workflow-stadia-title">{{ t('stadia.title') }}</span>
              <button
                type="button"
                class="btn btn-xs btn-secondary btn-icon-only stadia-save-default"
                :title="t('stadia.saveDefaultTitle')"
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
                <input
                  v-if="editingIdx === idx"
                  ref="editInput"
                  v-model="editName"
                  type="text"
                  class="form-control stadia-edit-input"
                  @click.stop
                  @keydown.enter.prevent="commitEdit(idx)"
                  @keydown.esc.prevent="cancelEdit"
                  @blur="commitEdit(idx)"
                >
                <span v-else class="stadia-name">{{ st.item.name || t('stadia.defaultName', { n: idx + 1 }) }}</span>
                <button
                  v-if="editingIdx !== idx"
                  type="button"
                  class="stadia-edit"
                  :title="t('stadia.editTitle')"
                  @click.stop.prevent="startEdit(idx)"
                >
                  <i class="modus-icons" style="font-size: 11px">edit</i>
                </button>
                <button
                  v-if="ui.stadia.length > 1 && editingIdx !== idx"
                  type="button"
                  class="stadia-delete"
                  :title="t('stadia.deleteTitle')"
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
                :placeholder="t('stadia.newPh')"
                @keydown.enter.prevent="addStadia"
              >
              <button type="button" class="btn btn-xs btn-primary" :title="t('stadia.addTitle')" @click="addStadia">
                <i class="modus-icons">add_circle</i> {{ t('stadia.addBtn') }}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, nextTick } from 'vue'
import { ui } from '../store.js'
import { t } from '../i18n/index.js'

function legacy(fn, ...args) {
  window.legacy?.[fn]?.(...args)
}

const newStadiaName = ref('')
function addStadia() {
  if (!newStadiaName.value.trim()) return
  legacy('addStadia', newStadiaName.value)
  newStadiaName.value = ''
}

// Инлайн-переименование стадии по иконке-карандашу
const editingIdx = ref(null)
const editName = ref('')
const editInput = ref(null)

function startEdit(idx) {
  editingIdx.value = idx
  editName.value = ui.stadia[idx]?.item.name || ''
  nextTick(() => {
    const el = Array.isArray(editInput.value) ? editInput.value[0] : editInput.value
    el?.focus()
    el?.select()
  })
}
function commitEdit(idx) {
  if (editingIdx.value !== idx) return
  editingIdx.value = null
  const name = editName.value.trim()
  if (!name || name === ui.stadia[idx]?.item.name) return
  legacy('renameStadia', idx, name)
}
function cancelEdit() {
  editingIdx.value = null
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
