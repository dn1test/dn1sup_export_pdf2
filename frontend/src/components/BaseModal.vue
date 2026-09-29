<template>
  <Teleport to="body">
    <Transition name="app-modal">
      <div v-if="open" class="modal-overlay" @mousedown.self="$emit('close')">
        <div
          ref="cardEl"
          class="modal-card"
          :class="cardClass"
          role="dialog"
          aria-modal="true"
          :aria-label="title"
          @keydown.tab="trapTab"
        >
          <slot />
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup>
import { nextTick, onBeforeUnmount, ref, watch } from 'vue'

const props = defineProps({
  open: { type: Boolean, default: false },
  title: { type: String, default: '' },
  cardClass: { type: String, default: '' },
})
const emit = defineEmits(['close'])

const cardEl = ref(null)

// ESC ловим на документе: фокус может быть и вне карточки
function onDocKeydown(e) {
  if (e.key === 'Escape') emit('close')
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
.app-modal-enter-active,
.app-modal-leave-active {
  transition: opacity 0.15s ease;
}
.app-modal-enter-from,
.app-modal-leave-to {
  opacity: 0;
}
</style>
