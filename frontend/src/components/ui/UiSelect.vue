<template>
  <select
    :value="modelValue"
    :title="title"
    class="h-8 w-full min-w-0 cursor-pointer appearance-none rounded-md border border-ink-200 bg-white px-1.5 pr-6 text-[13px] text-ink-900 transition-colors focus:border-accent-500 focus:outline-none focus:ring-2 focus:ring-accent-500/20 disabled:cursor-default disabled:bg-ink-50"
    :style="{ 'background-image': caret, 'background-repeat': 'no-repeat', 'background-position': 'right 6px center', 'background-size': '10px' }"
    @change="$emit('update:modelValue', $event.target.value)"
  >
    <slot />
  </select>
</template>

<script setup>
defineProps({
  modelValue: { type: [String, Number], default: '' },
  title: { type: String, default: '' },
})
defineEmits(['update:modelValue'])

// Своя каретка: нативная стрелка в CEF выглядит грубо
const caret =
  `url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='10' height='6' viewBox='0 0 10 6'%3E%3Cpath d='M1 1l4 4 4-4' fill='none' stroke='%2364748b' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E")`
</script>
