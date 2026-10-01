<template>
  <button
    type="button"
    class="inline-flex shrink-0 items-center justify-center gap-1.5 rounded-md font-medium whitespace-nowrap transition-colors focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-accent-500 disabled:pointer-events-none disabled:opacity-45"
    :class="[sizeCls, variantCls, $attrs.class]"
    :title="title"
    :disabled="disabled"
  >
    <component :is="icon" v-if="icon" :size="iconSize" aria-hidden="true" />
    <slot />
  </button>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  variant: { type: String, default: 'secondary' }, // primary|secondary|danger|danger-soft|success|ghost
  size: { type: String, default: 'sm' }, // xs|sm|md
  icon: { type: [Object, Function], default: null },
  title: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
})

const variantCls = computed(() => ({
  primary: 'bg-accent-600 text-white hover:bg-accent-700 active:bg-accent-700',
  secondary: 'border border-ink-200 bg-white text-ink-700 hover:border-ink-300 hover:bg-ink-50',
  danger: 'bg-red-600 text-white hover:bg-red-700',
  'danger-soft': 'border border-red-200 bg-white text-red-600 hover:bg-red-50',
  success: 'bg-emerald-600 text-white hover:bg-emerald-700',
  ghost: 'text-ink-500 hover:bg-ink-100 hover:text-ink-700',
}[props.variant] || ''))

const sizeCls = computed(() => ({
  xs: 'h-6 px-2 text-xs',
  sm: 'h-7 px-2.5 text-xs',
  md: 'h-8 px-3.5 text-[13px]',
}[props.size] || ''))

const iconSize = computed(() => (props.size === 'md' ? 15 : 13))
</script>
