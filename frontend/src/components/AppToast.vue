<template>
  <Teleport to="body">
    <Transition name="app-toast">
      <div
        v-if="ui.toast.visible"
        class="toast"
        :class="[ui.toast.type, `toast-${ui.toast.type}`]"
        role="status"
        aria-live="polite"
      >
        <i class="modus-icons">{{ ui.toast.icon }}</i> <span>{{ ui.toast.msg }}</span>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup>
import { ui } from '../store.js'
</script>

<style>
.app-toast-enter-active,
.app-toast-leave-active {
  transition: opacity 0.2s ease, transform 0.2s ease;
}
.app-toast-enter-from,
.app-toast-leave-to {
  opacity: 0;
  transform: translateY(-6px);
}
</style>
