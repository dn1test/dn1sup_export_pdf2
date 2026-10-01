<template>
  <label
    class="inline-flex cursor-pointer select-none items-center gap-1.5 text-[13px] text-ink-700"
    :title="title"
    @click.stop
  >
    <input
      type="checkbox"
      :checked="modelValue"
      class="size-3.5 cursor-pointer accent-accent-600"
      @change="$emit('update:modelValue', $event.target.checked)"
    >
    <span><slot /></span>
  </label>
</template>

<script setup>
defineProps({
  modelValue: { type: Boolean, default: false },
  title: { type: String, default: '' },
})
defineEmits(['update:modelValue'])
</script>
