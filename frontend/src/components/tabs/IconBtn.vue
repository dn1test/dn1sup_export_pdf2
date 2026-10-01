<template>
  <button
    type="button"
    class="flex size-6 shrink-0 items-center justify-center rounded-md text-ink-400 transition-colors hover:bg-ink-100 hover:text-ink-700 disabled:pointer-events-none disabled:opacity-30"
    :class="{ 'hover:bg-red-50 hover:text-red-500': danger }"
    :title="title"
    :disabled="disabled"
    @click.stop
  >
    <slot />
  </button>
</template>

<script setup>
defineProps({
  title: { type: String, default: '' },
  danger: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
})
</script>
