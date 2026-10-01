<template>
  <Teleport to="body">
    <Transition name="ui-modal">
      <div v-if="app.progress.visible" class="fixed inset-0 z-[70] flex items-center justify-center bg-ink-900/50 backdrop-blur-[2px]">
        <div class="flex w-80 flex-col items-center gap-3 rounded-xl bg-white px-6 py-6 shadow-pop">
          <Loader2Icon :size="28" class="animate-spin text-accent-600" />
          <h3 class="text-sm font-semibold text-ink-900">{{ t('progress.title') }}</h3>
          <p class="min-h-4 text-center text-xs text-ink-500">{{ app.progress.message }}</p>
          <div class="h-1.5 w-full overflow-hidden rounded-full bg-ink-100">
            <div class="h-full rounded-full bg-accent-600 transition-[width] duration-200" :style="{ width: `${app.progress.percent}%` }" />
          </div>
          <span class="font-mono text-xs text-ink-500">{{ app.progress.percent }}%</span>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup>
import { Loader2 } from '@lucide/vue'
import { t } from '../../i18n/index.js'
import { useAppStore } from '../../stores/app.js'

const app = useAppStore()
const Loader2Icon = Loader2
</script>
