<template>
  <Teleport to="body">
    <Transition name="ui-modal">
      <div
        v-if="open"
        class="fixed inset-0 z-50 flex items-center justify-center bg-ink-900/40 p-4"
        @mousedown.self="close"
      >
        <div
          ref="cardEl"
          class="flex max-h-[90vh] w-full flex-col overflow-hidden rounded-xl bg-white shadow-pop"
          :class="widthCls"
          role="dialog"
          aria-modal="true"
          :aria-label="title"
          @keydown.tab="trapTab"
        >
          <header v-if="title" class="flex items-center gap-3 border-b border-ink-100 px-5 py-3.5">
            <span
              class="flex size-9 shrink-0 items-center justify-center rounded-lg"
              :class="danger ? 'bg-red-50 text-red-600' : 'bg-accent-50 text-accent-600'"
            >
              <component :is="icon" v-if="icon" :size="18" aria-hidden="true" />
            </span>
            <div class="min-w-0">
              <h3 class="text-sm font-semibold text-ink-900">{{ title }}</h3>
              <p v-if="subtitle" class="text-xs text-ink-500">{{ subtitle }}</p>
            </div>
            <button
              type="button"
              class="ml-auto flex size-7 items-center justify-center rounded-md text-ink-400 hover:bg-ink-100 hover:text-ink-600"
              aria-label="close"
              @click="close"
            >
              <XIcon :size="15" />
            </button>
          </header>
          <div class="min-h-0 flex-1 overflow-y-auto px-5 py-4">
            <slot />
          </div>
          <footer v-if="$slots.footer" class="flex items-center justify-end gap-2 border-t border-ink-100 bg-ink-50/60 px-5 py-3">
            <slot name="footer" />
          </footer>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup>
import { nextTick, onBeforeUnmount, ref, watch, computed } from 'vue'
import { X as XIcon } from '@lucide/vue'

const props = defineProps({
  open: { type: Boolean, default: false },
  title: { type: String, default: '' },
  subtitle: { type: String, default: '' },
  icon: { type: [Object, Function], default: null },
  danger: { type: Boolean, default: false },
  width: { type: String, default: 'sm' }, // xs|sm|md|lg
})
const emit = defineEmits(['close'])

const widthCls = computed(() => ({
  xs: 'max-w-sm',
  sm: 'max-w-md',
  md: 'max-w-lg',
  lg: 'max-w-2xl',
}[props.width] || 'max-w-md'))

const cardEl = ref(null)

function close() {
  emit('close')
}

function onDocKeydown(e) {
  if (e.key === 'Escape') close()
}

watch(
  () => props.open,
  (open) => {
    if (open) {
      document.addEventListener('keydown', onDocKeydown)
      nextTick(() => {
        const card = cardEl.value
        if (!card) return
        const target = card.querySelector('input, select, textarea')
        if (target) target.focus()
      })
    } else {
      document.removeEventListener('keydown', onDocKeydown)
    }
  },
  { immediate: true },
)

onBeforeUnmount(() => document.removeEventListener('keydown', onDocKeydown))

function trapTab(e) {
  const card = cardEl.value
  if (!card) return
  const focusables = Array.from(
    card.querySelectorAll(
      'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
    ),
  )
  if (!focusables.length) return
  const first = focusables[0]
  const last = focusables[focusables.length - 1]
  const active = document.activeElement
  if (e.shiftKey && active === first) {
    e.preventDefault()
    last.focus()
  } else if (!e.shiftKey && active === last) {
    e.preventDefault()
    first.focus()
  }
}
</script>

<style>
.ui-modal-enter-active,
.ui-modal-leave-active {
  transition: opacity 0.15s ease;
}
.ui-modal-enter-active .rounded-xl,
.ui-modal-leave-active .rounded-xl {
  transition: transform 0.15s ease;
}
.ui-modal-enter-from,
.ui-modal-leave-to {
  opacity: 0;
}
.ui-modal-enter-from .rounded-xl {
  transform: translateY(6px) scale(0.98);
}
</style>
