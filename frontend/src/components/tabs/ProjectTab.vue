<template>
  <div class="flex flex-col gap-3">
    <!-- Паспорт объекта + Карточка заказчика -->
    <div class="grid grid-cols-2 gap-3">
      <UiCard :title="t('project.title')">
        <template #icon><ClipboardListIcon :size="14" /></template>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <UiField class="sm:col-span-2" :label="t('project.furnitureLabel')">
            <UiInput v-model="project.project.product" :placeholder="t('project.furniturePh')" @update:model-value="onProductInput" />
          </UiField>
          <UiField class="sm:col-span-1" :label="t('project.roomLabel')">
            <UiInput v-model="project.project.place" :placeholder="t('project.roomPh')" @update:model-value="notifyChange()" />
          </UiField>
          <UiField class="sm:col-span-1" :label="t('project.addressLabel')">
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
              <UiInput v-model="project.customer.id" :spellcheck="false" class="flex-1 font-mono" placeholder="CUST-260905-142650" @update:model-value="notifyChange()" />
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
        <div class="flex flex-col gap-3 p-3.5">
          <!-- Ряд 1: Автор + финансы (Ставка / Время / Стоимость) -->
          <div class="grid grid-cols-[38fr_62fr] gap-3">
            <UiField :label="t('workflow.authorLabel')">
              <UiInput v-model="project.workflow.author" :placeholder="t('workflow.authorPh')" @update:model-value="notifyChange()" />
            </UiField>

            <div>
              <div class="grid grid-cols-3 pb-1">
                <label class="truncate text-xs font-medium text-ink-500" :title="t('workflow.rateLabel')">{{ t('workflow.rateLabel') }}</label>
                <label class="truncate text-xs font-medium text-ink-500" :title="t('workflow.durationLabel')">{{ t('workflow.durationLabel') }}</label>
                <label class="truncate text-xs font-medium text-ink-500" :title="t('workflow.priceLabel')">{{ t('workflow.priceLabel') }}</label>
              </div>
              <div class="flex rounded-md border border-ink-200 bg-white divide-x divide-ink-200 transition-colors focus-within:border-accent-500 focus-within:ring-2 focus-within:ring-accent-500/20">
                <div class="flex min-w-0 flex-1 items-center">
                  <UiInput v-model="project.workflow.rate" plain class="text-right" :title="t('workflow.rateLabel')" :placeholder="t('workflow.rateShortPh')" @update:model-value="onAutoCostInput" />
                  <span class="shrink-0 pr-2 text-[11px] text-ink-400">₽/ч</span>
                </div>
                <div class="min-w-0 flex-1">
                  <UiInput v-model="project.workflow.total_duration" plain :title="t('workflow.durationLabel')" :placeholder="t('workflow.durationPh')" @update:model-value="onAutoCostInput" />
                </div>
                <div class="min-w-0 flex-1">
                  <UiInput v-model="project.workflow.price" plain :title="t('workflow.priceAutoTitle')" :placeholder="t('workflow.pricePh')" @update:model-value="notifyChange()" />
                </div>
              </div>
            </div>
          </div>

          <!-- Ряд 2: Вариант / Ревизия + Старт / Сдача проекта -->
          <div class="grid grid-cols-[38fr_62fr] gap-3">
            <div>
              <div class="grid grid-cols-2 pb-1">
                <label class="truncate text-xs font-medium text-ink-500" :title="t('workflow.versionLabel')">{{ t('workflow.versionLabel') }}</label>
                <label class="truncate text-xs font-medium text-ink-500" :title="t('workflow.revisionLabel')">{{ t('workflow.revisionLabel') }}</label>
              </div>
              <div class="flex rounded-md border border-ink-200 bg-white divide-x divide-ink-200 transition-colors focus-within:border-accent-500 focus-within:ring-2 focus-within:ring-accent-500/20">
                <div class="min-w-0 flex-1">
                  <UiInput
                    v-model="project.workflow.version"
                    plain
                    type="number"
                    min="1"
                    class="text-center font-mono font-medium [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
                    :title="t('workflow.versionLabel')"
                    @update:model-value="notifyChange()"
                  />
                </div>
                <div class="min-w-0 flex-1">
                  <UiInput
                    v-model="project.workflow.revision"
                    plain
                    type="number"
                    min="1"
                    class="text-center font-mono font-medium [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
                    :title="t('workflow.revisionLabel')"
                    @update:model-value="notifyChange()"
                  />
                </div>
              </div>
            </div>

            <div>
              <div class="grid grid-cols-2 pb-1">
                <label class="truncate text-xs font-medium text-ink-500" :title="t('workflow.startProjectLabel')">{{ t('workflow.startProjectLabel') }}</label>
                <label class="truncate text-xs font-medium text-ink-500" :title="t('workflow.endProjectLabel')">{{ t('workflow.endProjectLabel') }}</label>
              </div>
              <div class="flex rounded-md border border-ink-200 bg-white divide-x divide-ink-200 transition-colors focus-within:border-accent-500 focus-within:ring-2 focus-within:ring-accent-500/20">
                <div class="min-w-0 flex-1">
                  <UiDateField
                    v-model="project.workflow.start_date"
                    plain
                    :placeholder="t('workflow.startDatePh')"
                    :pick-title="t('workflow.pickDate')"
                    @update:model-value="notifyChange()"
                  />
                </div>
                <div class="min-w-0 flex-1">
                  <UiDateField
                    v-model="project.workflow.end_date"
                    plain
                    :placeholder="t('workflow.endDatePh')"
                    :pick-title="t('workflow.pickDate')"
                    @update:model-value="notifyChange()"
                  />
                </div>
              </div>
            </div>
          </div>

          <!-- Комментарий к последней правке -->
          <UiField :label="t('workflow.lastEditLabel')">
            <UiInput v-model="project.lastEdit" :placeholder="t('workflow.lastEditPh')" @update:model-value="notifyChange()" />
          </UiField>

          <!-- Спецификации -->
          <div class="grid grid-cols-2 gap-3">
            <UiField :label="t('workflow.materialsLabel')">
              <UiTextarea v-model="project.project.materials" :rows="6" :placeholder="t('workflow.materialsPh')" @update:model-value="onSpecsChanged" />
            </UiField>
            <UiField :label="t('workflow.lightingLabel')">
              <UiTextarea v-model="project.project.lighting" :rows="6" :placeholder="t('workflow.lightingPh')" @update:model-value="onSpecsChanged" />
            </UiField>
          </div>
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
                ref="editInput"
                v-model="editName"
                type="text"
                spellcheck="false"
                v-spell
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

// Правка Ставки/Времени: автопересчёт стоимости (Ставка × Время) + автосохранение
function onAutoCostInput() {
  project.recalcPrice()
  notifyChange()
}

// Изделие: product_tags — зеркало строки «Изделие» (как на Ruby-прокси).
// Без синка на вводе payload уходит со старым значением из тегов
// (furnitureName предпочитает непустые теги), и правка откатывается
function onProductInput(val) {
  project.syncProductTags(val)
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
