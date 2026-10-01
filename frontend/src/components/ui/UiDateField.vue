<template>
  <!-- Ввод «дд.мм.гггг» + спрятанный нативный календарь (CEF рисует
       американсий порядок — календарь открывается только по иконке) -->
  <div class="relative flex">
    <input
      :value="display"
      type="text"
      class="h-8 w-full min-w-0 rounded-md border border-ink-200 bg-white pr-8 pl-2.5 text-[13px] text-ink-900 transition-colors placeholder:text-ink-400 focus:border-accent-500 focus:outline-none focus:ring-2 focus:ring-accent-500/20"
      :placeholder="placeholder"
      inputmode="numeric"
      maxlength="10"
      @focus="lastValid = display"
      @input="display = $event.target.value"
      @blur="commit"
      @keydown.enter.prevent="$event.target.blur()"
    >
    <input
      ref="nativeEl"
      :value="modelValue"
      type="date"
      class="sr-only"
      tabindex="-1"
      aria-hidden="true"
      @change="onNativeChange"
    >
    <button
      type="button"
      class="absolute top-1/2 right-1 flex size-6 -translate-y-1/2 items-center justify-center rounded text-ink-400 hover:bg-ink-100 hover:text-accent-600"
      :title="pickTitle"
      @click="openPicker"
    >
      <CalendarIcon :size="14" />
    </button>
  </div>
</template>

<script setup>
import { ref, watch } from 'vue'
import { Calendar as CalendarIcon } from '@lucide/vue'
import { isoToRuDate, parseRuDate } from '../../lib/dates.js'

const props = defineProps({
  modelValue: { type: String, default: '' },
  placeholder: { type: String, default: '' },
  pickTitle: { type: String, default: '' },
})
const emit = defineEmits(['update:modelValue'])

const display = ref(isoToRuDate(props.modelValue))
const lastValid = ref(display.value)
const nativeEl = ref(null)

watch(
  () => props.modelValue,
  (v) => {
    display.value = v ? isoToRuDate(v) : ''
    lastValid.value = display.value
  },
)

function commit() {
  const raw = display.value.trim()
  if (!raw) {
    display.value = ''
    lastValid.value = ''
    emit('update:modelValue', '')
    return
  }
  const iso = parseRuDate(raw)
  if (iso) {
    display.value = isoToRuDate(iso)
    lastValid.value = display.value
    emit('update:modelValue', iso)
  } else {
    // Некорректный ввод — возвращаем последнюю согласованную дату
    display.value = lastValid.value || ''
    emit('update:modelValue', parseRuDate(display.value) || '')
  }
}

function onNativeChange(e) {
  const v = e.target.value
  display.value = v ? isoToRuDate(v) : ''
  lastValid.value = display.value
  emit('update:modelValue', v)
}

function openPicker() {
  if (nativeEl.value && typeof nativeEl.value.showPicker === 'function') {
    try {
      nativeEl.value.showPicker()
    } catch (err) {
      // CEF может запретить showPicker — поле остаётся клавиатурным
    }
  }
}
</script>
