<template>
  <div class="flex flex-col items-center justify-center gap-1.5 px-6 py-10 text-center">
    <span v-if="$slots.icon" class="text-ink-300">
      <slot name="icon" />
    </span>
    <div class="text-[13px] font-medium text-ink-500">{{ title }}</div>
    <div v-if="hint" class="max-w-sm text-xs text-ink-400">{{ hint }}</div>
  </div>
</template>

<script setup>
defineProps({
  title: { type: String, default: '' },
  hint: { type: String, default: '' },
})
</script>
