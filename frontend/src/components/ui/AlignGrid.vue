<template>
  <!-- Сетка выравнивания 3×3 (центр может быть исключён) -->
  <div class="grid grid-cols-3 gap-1">
    <template v-for="cell in cells" :key="cell.key">
      <button
        v-if="!cell.excluded"
        type="button"
        class="flex size-8 items-center justify-center rounded-md border transition-colors"
        :class="cell.active
          ? 'border-accent-500 bg-accent-50 text-accent-600'
          : 'border-ink-200 text-ink-500 hover:border-ink-300 hover:bg-ink-50 hover:text-ink-700'"
        :title="cell.title"
        @click="$emit('pick', cell.h, cell.v)"
      >
        <component :is="cell.icon" :size="14" />
      </button>
      <span v-else class="size-8 rounded-md border border-dashed border-ink-200" />
    </template>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import {
  ArrowUpLeft, ArrowUp, ArrowUpRight,
  ArrowLeft, Circle, ArrowRight,
  ArrowDownLeft, ArrowDown, ArrowDownRight,
} from '@lucide/vue'
import { t } from '../../i18n/index.js'

const props = defineProps({
  h: { type: String, default: 'center' },
  v: { type: String, default: 'center' },
  excludeCenter: { type: Boolean, default: false },
})
defineEmits(['pick'])

const H = () => ({ left: t('scenes.alignH.left'), center: t('scenes.alignH.center'), right: t('scenes.alignH.right') })
const V = () => ({ top: t('scenes.alignV.top'), center: t('scenes.alignV.center'), bottom: t('scenes.alignV.bottom') })

const cells = computed(() => {
  const rows = [
    { v: 'top', icons: [ArrowUpLeft, ArrowUp, ArrowUpRight] },
    { v: 'center', icons: [ArrowLeft, Circle, ArrowRight] },
    { v: 'bottom', icons: [ArrowDownLeft, ArrowDown, ArrowDownRight] },
  ]
  const hs = ['left', 'center', 'right']
  const out = []
  rows.forEach((row) => {
    hs.forEach((h, i) => {
      out.push({
        key: `${h}|${row.v}`,
        h,
        v: row.v,
        icon: row.icons[i],
        excluded: props.excludeCenter && h === 'center' && row.v === 'center',
        active: props.h === h && props.v === row.v,
        title: `${H()[h] || h} · ${V()[row.v] || row.v}`,
      })
    })
  })
  return out
})
</script>
