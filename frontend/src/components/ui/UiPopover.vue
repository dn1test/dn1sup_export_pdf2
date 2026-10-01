<template>
  <Teleport to="body">
    <div
      v-if="open && pos"
      ref="popEl"
      class="fixed z-50 rounded-lg border border-ink-200 bg-white p-2 shadow-pop"
      :style="pos"
      @mousedown.stop
      @click.stop
    >
      <slot />
    </div>
  </Teleport>
</template>

<script setup>
import { nextTick, onBeforeUnmount, ref, watch } from 'vue'

// Поповер у якорного элемента: по центру, снизу; при нехватке места — сверху.
// Закрытие: клик мимо, Esc.
const props = defineProps({
  open: { type: Boolean, default: false },
  anchor: { type: HTMLElement, default: null },
})
const emit = defineEmits(['close'])

const popEl = ref(null)
const pos = ref(null)

function position() {
  if (!props.anchor) return
  const r = props.anchor.getBoundingClientRect()
  const x = Math.round(r.left + r.width / 2)
  const el = popEl.value
  let top = Math.round(r.bottom + 6)
  let transform = 'translateX(-50%)'
  if (el) {
    const spaceBelow = window.innerHeight - r.bottom
    if (spaceBelow < el.offsetHeight + 8) {
      top = Math.round(r.top)
      transform = 'translate(-50%, calc(-100% - 6px))'
    }
  }
  pos.value = { left: `${x}px`, top: `${top}px`, transform }
}

function onDocMousedown(e) {
  const t = e.target
  if (popEl.value && popEl.value.contains(t)) return
  if (props.anchor && props.anchor.contains(t)) return
  emit('close')
}
function onDocKeydown(e) {
  if (e.key === 'Escape') emit('close')
}

watch(
  () => props.open,
  (open) => {
    if (open) {
      pos.value = { left: '-9999px', top: '0px' }
      nextTick(() => {
        position()
        // Реверс: сначала рендер вне экрана для замера высоты, затем позиция
        position()
        setTimeout(() => {
          document.addEventListener('mousedown', onDocMousedown)
          document.addEventListener('keydown', onDocKeydown)
        }, 0)
      })
    } else {
      pos.value = null
      document.removeEventListener('mousedown', onDocMousedown)
      document.removeEventListener('keydown', onDocKeydown)
    }
  },
)

onBeforeUnmount(() => {
  document.removeEventListener('mousedown', onDocMousedown)
  document.removeEventListener('keydown', onDocKeydown)
})
</script>
