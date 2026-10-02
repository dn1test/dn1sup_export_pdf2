<template>
  <input
    :value="modelValue"
    :type="type"
    :placeholder="placeholder"
    :title="title"
    :readonly="readonly"
    :min="min"
    :max="max"
    :step="step"
    :autocomplete="autocomplete"
    :class="plain ? plainClass : boxClass"
    @input="$emit('update:modelValue', $event.target.value)"
    @change="$emit('change', $event)"
    @keydown.enter="$emit('enter', $event)"
  >
</template>

<script setup>
defineProps({
  modelValue: { type: [String, Number], default: '' },
  type: { type: String, default: 'text' },
  placeholder: { type: String, default: '' },
  title: { type: String, default: '' },
  readonly: { type: Boolean, default: false },
  min: { type: [String, Number], default: undefined },
  max: { type: [String, Number], default: undefined },
  step: { type: [String, Number], default: undefined },
  autocomplete: { type: String, default: 'off' },
  // Без своей рамки — для сегментных групп, где рамку рисует контейнер
  plain: { type: Boolean, default: false },
})
defineEmits(['update:modelValue', 'change', 'enter'])

const boxClass = 'h-8 w-full min-w-0 rounded-md border border-ink-200 bg-white px-2.5 text-[13px] text-ink-900 transition-colors placeholder:text-ink-400 focus:border-accent-500 focus:outline-none focus:ring-2 focus:ring-accent-500/20 read-only:bg-ink-50 read-only:text-ink-500'
const plainClass = 'h-8 w-full min-w-0 bg-transparent px-2.5 text-[13px] text-ink-900 transition-colors placeholder:text-ink-400 focus:outline-none read-only:text-ink-500'
</script>
