<template>
  <textarea
    :value="modelValue"
    :rows="rows"
    :placeholder="placeholder"
    :title="title"
    class="w-full resize-y rounded-md border border-ink-200 bg-white px-2.5 py-1.5 text-[13px] leading-snug text-ink-900 transition-colors placeholder:text-ink-400 focus:border-accent-500 focus:outline-none focus:ring-2 focus:ring-accent-500/20"
    @input="$emit('update:modelValue', $event.target.value)"
  />
</template>

<script setup>
defineProps({
  modelValue: { type: String, default: '' },
  rows: { type: [String, Number], default: 3 },
  placeholder: { type: String, default: '' },
  title: { type: String, default: '' },
})
defineEmits(['update:modelValue'])
</script>
