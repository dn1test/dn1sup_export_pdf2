<template>
  <Teleport to="body">
    <Transition name="ui-toast">
      <div
        v-if="toast.visible"
        class="fixed top-3 left-1/2 z-[60] flex max-w-[80%] items-center gap-2 rounded-lg px-3.5 py-2 text-[13px] font-medium shadow-pop"
        :class="cls"
        role="status"
        aria-live="polite"
      >
        <component :is="icon" :size="15" />
        <span>{{ toast.msg }}</span>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup>
import { computed } from 'vue'
import { CheckCircle2, XCircle, AlertTriangle, Info } from '@lucide/vue'
import { toast } from '../../stores/toast.js'

const cls = computed(() => ({
  success: 'bg-emerald-600 text-white',
  error: 'bg-red-600 text-white',
  warning: 'bg-amber-500 text-white',
  info: 'bg-ink-900 text-white',
}[toast.value.type] || 'bg-ink-900 text-white'))

const icon = computed(() => ({
  success: CheckCircle2,
  error: XCircle,
  warning: AlertTriangle,
  info: Info,
}[toast.value.type] || Info))
</script>

<style>
.ui-toast-enter-active,
.ui-toast-leave-active {
  transition: opacity 0.2s ease, transform 0.2s ease;
}
.ui-toast-enter-from,
.ui-toast-leave-to {
  opacity: 0;
  transform: translate(-50%, -8px);
}
</style>
