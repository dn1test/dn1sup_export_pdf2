<template>
  <section class="rounded-lg border border-ink-200 bg-white shadow-card" :class="$attrs.class">
    <header
      v-if="title || $slots.actions || $slots.icon"
      class="flex min-h-11 items-center gap-2 border-b border-ink-100 px-3.5 py-2"
    >
      <span v-if="$slots.icon" class="flex size-6 items-center justify-center rounded-md bg-accent-50 text-accent-600">
        <slot name="icon" />
      </span>
      <h2 class="truncate text-[13px] font-semibold text-ink-900" :title="title">{{ title }}</h2>
      <div class="ml-auto flex items-center gap-1.5">
        <slot name="actions" />
      </div>
    </header>
    <div class="p-3.5" :class="bodyClass">
      <slot />
    </div>
  </section>
</template>

<script setup>
defineProps({
  title: { type: String, default: '' },
  bodyClass: { type: String, default: '' },
})
</script>
