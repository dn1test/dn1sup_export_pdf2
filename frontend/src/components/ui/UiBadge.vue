<template>
  <span
    class="inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-[11px] font-medium whitespace-nowrap"
    :class="variantCls"
    :title="title"
  >
    <slot />
  </span>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  variant: { type: String, default: 'neutral' }, // neutral|accent|success|warn|danger|outline
  title: { type: String, default: '' },
})

const variantCls = computed(() => ({
  neutral: 'bg-ink-100 text-ink-500',
  accent: 'bg-accent-50 text-accent-700',
  success: 'bg-emerald-50 text-emerald-700',
  warn: 'bg-amber-50 text-amber-700',
  danger: 'bg-red-50 text-red-600',
  outline: 'border border-ink-200 text-ink-500',
}[props.variant] || ''))
</script>
