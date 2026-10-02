<template>
  <div class="flex flex-col gap-3">
    <!-- Паспорт объекта + Карточка заказчика -->
    <div class="grid grid-cols-2 gap-3">
      <UiCard :title="t('project.title')">
        <template #icon><ClipboardListIcon :size="14" /></template>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <UiField class="sm:col-span-3" :label="t('project.furnitureLabel')">
            <UiInput v-model="project.project.product" :placeholder="t('project.furniturePh')" @update:model-value="notifyChange()" />
          </UiField>
          <UiField class="sm:col-span-1" :label="t('project.roomLabel')">
            <UiInput v-model="project.project.place" :placeholder="t('project.roomPh')" @update:model-value="notifyChange()" />
          </UiField>
          <UiField class="sm:col-span-2" :label="t('project.addressLabel')">
            <UiInput v-model="project.project.adress" :placeholder="t('project.addressPh')" @update:model-value="notifyChange()" />
          </UiField>
        </div>
      </UiCard>

      <UiCard :title="t('customer.title')">
        <template #icon><UserIcon :size="14" /></template>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <UiField :label="t('customer.nameLabel')">
            <UiInput v-model="project.customer.name" :placeholder="t('customer.namePh')" @update:model-value="notifyChange()" />
          </UiField>
          <UiField :label="t('customer.idLabel')">
            <div class="flex gap-1.5">
              <UiInput v-model="project.customer.id" class="flex-1 font-mono" placeholder="CUST-260905-142650" @update:model-value="notifyChange()" />
              <UiButton
                :icon="WandIcon"
                :title="t('customer.idGenTitle')"
                :aria-label="t('customer.idGenAria')"
                @click="generateCustomerId"
              />
            </div>
          </UiField>
          <UiField v-if="project.isCommercial" class="sm:col-span-2" :label="t('customer.companyLabel')">
            <UiInput v-model="project.customer.company" placeholder="ООО &quot;Техно-Дизайн&quot;, ТЦ &quot;Атриум&quot;" @update:model-value="notifyChange()" />
          </UiField>
          <UiField :label="t('customer.phoneLabel')">
            <UiInput v-model="project.customer.phone" placeholder="+7 (999) 000-00-00" @update:model-value="notifyChange()" />
          </UiField>
          <UiField :label="t('customer.emailLabel')">
            <UiInput v-model="project.customer.email" type="email" placeholder="client@example.com" @update:model-value="notifyChange()" />
          </UiField>
        </div>
      </UiCard>
    </div>

    <!-- Ход работы + стадии -->
    <UiCard :title="t('workflow.title')" body-class="p-0 @container">
      <template #icon><ClockIcon :size="14" /></template>
      <div class="grid grid-cols-[1fr_300px] gap-0">
        <!-- Левая колонка: параметры -->
        <div class="grid grid-cols-1 gap-x-3 gap-y-3 p-3.5 @min-[900px]:grid-cols-2">
          <!-- Автор / Конструктор -->
          <UiField :label="t('workflow.authorLabel')">
            <UiInput v-model="project.workflow.author" :placeholder="t('workflow.authorPh')" @update:model-value="notifyChange()" />
          </UiField>

          <!-- Финансы: Стоимость + Ставка -->
          <div class="flex items-end gap-2">
            <UiField class="flex-1 min-w-0" :label="t('workflow.priceLabel')">
              <UiInput v-model="project.workflow.price" :placeholder="t('workflow.pricePh')" @update:model-value="notifyChange()" />
            </UiField>
            <UiField class="w-28 shrink-0" :label="t('workflow.rateLabel')">
              <div class="flex items-center gap-1">
                <UiInput v-model="project.workflow.rate" class="text-right" :placeholder="t('workflow.rateShortPh')" @update:model-value="notifyChange()" />
                <span class="text-[11px] text-ink-400 shrink-0">₽/ч</span>
              </div>
            </UiField>
          </div>

          <!-- Сроки проекта: Начало — Сдача (объединённый блок) -->
          <UiField :label="t('workflow.datesGroupLabel')">
            <div class="flex items-center gap-1.5">
              <UiDateField
                v-model="project.workflow.start_date"
                class="flex-1 min-w-0"
                :title="t('workflow.startDate')"
                :placeholder="t('workflow.startDatePh')"
                :pick-title="t('workflow.pickDate')"
                @update:model-value="notifyChange()"
              />
              <span class="text-ink-400 font-medium px-0.5 select-none shrink-0" title="—">—</span>
              <UiDateField
                v-model="project.workflow.end_date"
                class="flex-1 min-w-0"
                :title="t('workflow.endDate')"
                :placeholder="t('workflow.endDatePh')"
                :pick-title="t('workflow.pickDate')"
                @update:model-value="notifyChange()"
              />
            </div>
          </UiField>

          <!-- Версия / Ревизия (компактный блок) + Длительность проекта -->
          <div class="flex items-end gap-2">
            <UiField class="shrink-0" :label="t('workflow.verRevGroupLabel')">
              <div class="flex items-center gap-1">
                <div class="relative flex items-center">
                  <span class="absolute left-1.5 text-[10px] font-semibold text-ink-400 select-none pointer-events-none">v.</span>
                  <UiInput
                    v-model="project.workflow.version"
                    type="number"
                    min="1"
                    class="!w-[68px] pl-5 pr-1.5 text-center font-mono font-medium [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
                    :title="t('workflow.versionLabel')"
                    @update:model-value="notifyChange()"
                  />
                </div>
                <span class="text-ink-300 font-mono text-xs select-none">#</span>
                <div class="relative flex items-center">
                  <span class="absolute left-1.5 text-[10px] font-semibold text-ink-400 select-none pointer-events-none">r.</span>
                  <UiInput
                    v-model="project.workflow.revision"
                    type="number"
                    min="1"
                    class="!w-[68px] pl-5 pr-1.5 text-center font-mono font-medium [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
                    :title="t('workflow.revisionLabel')"
                    @update:model-value="notifyChange()"
                  />
                </div>
              </div>
            </UiField>
            <UiField class="flex-1 min-w-0" :label="t('workflow.durationLabel')">
              <UiInput v-model="project.workflow.total_duration" :placeholder="t('workflow.durationPh')" @update:model-value="notifyChange()" />
            </UiField>
          </div>

          <!-- Комментарий к последней правке -->
          <UiField class="@min-[900px]:col-span-2" :label="t('workflow.lastEditLabel')">
            <UiInput v-model="project.lastEdit" :placeholder="t('workflow.lastEditPh')" @update:model-value="notifyChange()" />
          </UiField>

          <!-- Спецификации -->
          <UiField :label="t('workflow.materialsLabel')">
            <UiTextarea v-model="project.project.materials" :rows="4" :placeholder="t('workflow.materialsPh')" @update:model-value="onSpecsChanged" />
          </UiField>
          <UiField :label="t('workflow.lightingLabel')">
            <UiTextarea v-model="project.project.lighting" :rows="4" :placeholder="t('workflow.lightingPh')" @update:model-value="onSpecsChanged" />
          </UiField>
        </div>

        <!-- Правая колонка: стадии -->
        <div class="flex flex-col border-l border-ink-100">
          <div class="flex items-center gap-2 px-3.5 py-2.5">
            <CheckSquareIcon :size="14" class="text-ink-400" />
            <span class="text-[13px] font-semibold text-ink-900">{{ t('stadia.title') }}</span>
            <UiButton
              class="ml-auto"
              size="xs"
              variant="ghost"
              :icon="SaveIcon"
              :title="t('stadia.saveDefaultTitle')"
              @click="project.saveStadiaDefault()"
            />
          </div>
          <div class="flex min-h-0 flex-1 flex-col gap-0.5 overflow-y-auto px-2 pb-2">
            <div
              v-for="(st, idx) in project.workflow.stadia"
              :key="idx"
              class="group flex items-center gap-2 rounded-md border px-2 py-1.5 transition-colors"
              :class="[
                drag.rowClasses(idx),
                st.status ? 'border-emerald-100 bg-emerald-50/50' : 'border-transparent hover:border-ink-200 hover:bg-ink-50',
              ]"
              :draggable="drag.dragArm.value === idx"
              @mousedown="drag.arm($event, idx)"
              @mouseup="drag.disarm()"
              @dragstart="drag.onDragStart($event, idx)"
              @dragover="drag.onDragOver($event, idx)"
              @dragleave="drag.clearOver()"
              @drop="drag.onDrop($event, idx)"
              @dragend="drag.clearDrag()"
            >
              <GripVerticalIcon :size="12" class="shrink-0 cursor-grab text-ink-300 opacity-0 transition-opacity group-hover:opacity-100" :title="t('scenes.dragTitle')" />
              <input
                v-model="st.status"
                type="checkbox"
                class="size-3.5 shrink-0 accent-emerald-600"
                @change="project.stadiaChanged()"
              >
              <input
                v-if="editingIdx === idx"
                v-model="editName"
                type="text"
                class="h-6 min-w-0 flex-1 rounded border border-accent-400 bg-white px-1.5 text-[13px] focus:outline-none"
                @click.stop
                @keydown.enter.prevent="commitEdit(idx)"
                @keydown.esc.prevent="editingIdx = null"
                @blur="commitEdit(idx)"
              >
              <span v-else class="min-w-0 flex-1 truncate text-[13px]" :class="st.status ? 'text-ink-900' : 'text-ink-500'" :title="st.name">
                {{ st.name || t('stadia.defaultName', { n: idx + 1 }) }}
              </span>
              <button
                v-if="editingIdx !== idx"
                type="button"
                class="flex size-5 shrink-0 items-center justify-center rounded text-ink-300 opacity-0 transition-opacity hover:bg-ink-100 hover:text-ink-600 group-hover:opacity-100"
                :title="t('stadia.editTitle')"
                @click.stop.prevent="startEdit(idx)"
              >
                <PencilIcon :size="11" />
              </button>
              <button
                v-if="project.workflow.stadia.length > 1 && editingIdx !== idx"
                type="button"
                class="flex size-5 shrink-0 items-center justify-center rounded text-ink-300 opacity-0 transition-opacity hover:bg-red-50 hover:text-red-500 group-hover:opacity-100"
                :title="t('stadia.deleteTitle')"
                @click.stop.prevent="project.removeStadia(idx)"
              >
                <XIcon :size="11" />
              </button>
            </div>

            <!-- Добавление стадии -->
            <div class="mt-1 flex gap-1.5">
              <UiInput
                v-model="newStadiaName"
                class="flex-1"
                :placeholder="t('stadia.newPh')"
                @enter="addStadia"
              />
              <UiButton size="sm" variant="primary" :icon="PlusIcon" :title="t('stadia.addTitle')" @click="addStadia">
                {{ t('stadia.addBtn') }}
              </UiButton>
            </div>
          </div>
        </div>
      </div>
    </UiCard>
  </div>
</template>

<script setup>
import { nextTick, ref } from 'vue'
import {
  ClipboardList, User, Wand2, Clock, CheckSquare, Save,
  GripVertical, Pencil, X, Plus,
} from '@lucide/vue'
import UiCard from '../ui/UiCard.vue'
import UiField from '../ui/UiField.vue'
import UiInput from '../ui/UiInput.vue'
import UiTextarea from '../ui/UiTextarea.vue'
import UiButton from '../ui/UiButton.vue'
import UiDateField from '../ui/UiDateField.vue'
import { t } from '../../i18n/index.js'
import { useProjectStore } from '../../stores/project.js'
import { useDirectoriesStore } from '../../stores/directories.js'
import { notifyChange } from '../../stores/autosave.js'
import { callRuby } from '../../bridge/sketchup.js'
import { useDragSort } from '../../composables/useDragSort.js'

const project = useProjectStore()
const dirs = useDirectoriesStore()

// Материалы/подсветка связаны с описаниями папок спецификаций
function onSpecsChanged() {
  dirs.syncSpecs()
  notifyChange()
}

// Генерация ID заказчика: в SketchUp — Ruby-генератор, в браузере — локальный
function generateCustomerId() {
  const name = String(project.customer.name || '').trim()
  if (window.sketchup && typeof window.sketchup.generateCustomerId === 'function') {
    callRuby('generateCustomerId', name)
    return
  }
  const now = new Date()
  const p = (n) => String(n).padStart(2, '0')
  const newId = `CUST-${String(now.getFullYear()).slice(-2)}${p(now.getMonth() + 1)}${p(now.getDate())}-${p(now.getHours())}${p(now.getMinutes())}${p(now.getSeconds())}`
  project.customer.id = newId
}

// --- Стадии: инлайн-переименование ---
const editingIdx = ref(null)
const editName = ref('')
const editInput = ref(null)

function startEdit(idx) {
  editingIdx.value = idx
  editName.value = project.workflow.stadia[idx]?.name || ''
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
  if (!name || name === project.workflow.stadia[idx]?.name) return
  project.renameStadia(idx, name)
}

// --- Стадии: drag & drop ---
const drag = useDragSort({
  onDrop: (from, to) => project.moveStadia(from, to),
})

// --- Добавление стадии ---
const newStadiaName = ref('')
function addStadia() {
  if (!newStadiaName.value.trim()) return
  project.addStadia(newStadiaName.value)
  newStadiaName.value = ''
}

const ClipboardListIcon = ClipboardList
const UserIcon = User
const WandIcon = Wand2
const ClockIcon = Clock
const CheckSquareIcon = CheckSquare
const SaveIcon = Save
const GripVerticalIcon = GripVertical
const PencilIcon = Pencil
const XIcon = X
const PlusIcon = Plus
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
