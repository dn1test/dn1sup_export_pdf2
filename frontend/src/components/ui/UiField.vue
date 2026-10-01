<template>
  <div class="flex min-w-0 flex-col gap-1" :class="$attrs.class">
    <label v-if="label" class="text-xs font-medium text-ink-500" :title="labelTitle">{{ label }}</label>
    <slot />
    <span v-if="hint" class="text-[11px] leading-tight text-ink-400">{{ hint }}</span>
  </div>
</template>

<script setup>
defineProps({
  label: { type: String, default: '' },
  labelTitle: { type: String, default: '' },
  hint: { type: String, default: '' },
})
</script>
