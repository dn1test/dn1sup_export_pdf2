<template>
  <div
    v-if="open"
    class="fixed z-[60] min-w-40 overflow-hidden rounded-md border border-ink-200 bg-white py-1 shadow-lg"
    :style="pos"
    @mousedown.prevent
  >
    <button
      v-for="s in suggestions"
      :key="s"
      type="button"
      class="block w-full cursor-pointer px-3 py-1.5 text-left text-[13px] text-ink-900 hover:bg-accent-50"
      @click="pick(s)"
    >{{ s }}</button>
    <div
      v-if="!suggestions.length"
      class="px-3 py-1.5 text-[13px] text-ink-400"
    >{{ t('spell.noSuggestions') }}</div>
    <div class="my-1 border-t border-ink-100" />
    <button
      type="button"
      class="block w-full cursor-pointer px-3 py-1.5 text-left text-[13px] text-ink-600 hover:bg-accent-50"
      @click="addToDict"
    >{{ t('spell.addToDict') }}</button>
  </div>
</template>

<script setup>
import { onBeforeUnmount, onMounted, ref } from 'vue'
import { t } from '../../i18n/index.js'
import { addUserWord, suggestFor } from '../../spellcheck/engine.js'
import { applySuggestion, refreshField } from '../../spellcheck/overlay.js'

const open = ref(false)
const suggestions = ref([])
const pos = ref({})
let ctx = null // { el, range } из события dn1-spell-menu

function place(x, y) {
  return {
    left: Math.max(4, Math.min(x, window.innerWidth - 190)) + 'px',
    top: Math.max(4, Math.min(y + 12, window.innerHeight - 150)) + 'px',
  }
}

function close() {
  open.value = false
  ctx = null
  document.removeEventListener('mousedown', onOutside, true)
  window.removeEventListener('keydown', onKey, true)
  window.removeEventListener('scroll', close, true)
  window.removeEventListener('resize', close)
}

function onOutside() {
  close()
}

function onKey(e) {
  if (e.key === 'Escape') close()
}

function onMenu(e) {
  close()
  ctx = e.detail
  suggestions.value = suggestFor(ctx.range.word)
  pos.value = place(ctx.x, ctx.y)
  open.value = true
  document.addEventListener('mousedown', onOutside, true)
  window.addEventListener('keydown', onKey, true)
  window.addEventListener('scroll', close, true)
  window.addEventListener('resize', close)
}

function pick(s) {
  if (!ctx) return
  applySuggestion(ctx.el, ctx.range, s)
  close()
}

function addToDict() {
  if (!ctx) return
  addUserWord(ctx.range.word)
  refreshField(ctx.el)
  close()
}

onMounted(() => window.addEventListener('dn1-spell-menu', onMenu))
onBeforeUnmount(() => {
  window.removeEventListener('dn1-spell-menu', onMenu)
  close()
})
</script>
