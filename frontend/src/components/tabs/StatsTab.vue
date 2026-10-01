<template>
  <div class="flex h-full min-h-0 flex-col gap-2.5">
    <!-- Тулбар -->
    <div class="flex flex-wrap items-center gap-2">
      <span class="text-[11px] text-ink-400">
        {{ t('stats.infoText') }}
        <template v-if="stats.articul"> — <span class="font-mono text-ink-600">{{ stats.articul }}</span></template>
        <template v-if="stats.product"> ({{ stats.product }})</template>
      </span>
      <div class="ml-auto flex items-center gap-1.5">
        <UiButton size="xs" :icon="RefreshIcon" :title="t('stats.refreshTitle')" @click="stats.refresh()">
          {{ t('stats.refreshBtn') }}
        </UiButton>
        <UiButton
          size="xs"
          :variant="confirmArmed ? 'danger' : 'secondary'"
          :icon="TrashIcon"
          :title="confirmArmed ? t('stats.resetConfirmTitle') : t('stats.resetTitle')"
          @click="onResetClick"
        >
          {{ confirmArmed ? t('stats.resetConfirmBtn') : t('stats.resetBtn') }}
        </UiButton>
      </div>
    </div>

    <div v-if="stats.error" class="rounded-md bg-red-50 px-3 py-1.5 text-xs text-red-600">{{ stats.error }}</div>

    <!-- Карточки-переключатели разрезов -->
    <div class="grid grid-cols-2 gap-2 lg:grid-cols-4" role="group" :aria-label="t('stats.cardsAria')">
      <button
        v-for="c in cards"
        :key="c.key"
        type="button"
        class="flex flex-col gap-0.5 rounded-lg border px-3.5 py-2.5 text-left transition-colors focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-accent-500"
        :class="range === c.key
          ? 'border-accent-500 bg-accent-50 shadow-[inset_0_0_0_1px_var(--color-accent-500)]'
          : 'border-ink-200 bg-white hover:border-accent-200 hover:bg-accent-50/40'"
        @click="range = c.key"
      >
        <span class="flex items-center gap-1.5 text-[11px] tracking-wide text-ink-500 uppercase">
          {{ t(c.labelKey) }}
          <span v-if="c.key === 'hourly' && todayDate" class="rounded bg-ink-100 px-1 font-mono text-[10px] tracking-normal text-ink-500">{{ todayDate }}</span>
        </span>
        <span class="text-lg font-semibold whitespace-nowrap" :class="c.total ? 'text-accent-700' : 'text-ink-900'">
          {{ fmt(report?.[c.seconds]) }}
        </span>
      </button>
    </div>

    <!-- График -->
    <div class="flex min-h-0 flex-1 flex-col rounded-lg border border-ink-200 bg-white p-3">
      <div class="relative min-h-[240px] flex-1">
        <canvas ref="canvasRef" />
        <div v-if="isEmpty" class="absolute inset-0 flex items-center justify-center px-10 text-center text-[13px] text-ink-400">
          {{ t('stats.empty') }}
        </div>
      </div>
    </div>

    <div v-if="report && !report.empty" class="flex flex-wrap gap-x-6 gap-y-1 text-[11px] text-ink-500">
      <span>{{ t('stats.firstActivity') }} <b class="font-mono text-ink-700">{{ report.first_tracked || '—' }}</b></span>
      <span>{{ t('stats.lastActivity') }} <b class="font-mono text-ink-700">{{ report.last_tracked || '—' }}</b></span>
      <span v-if="stats.savedAt">{{ t('stats.updated') }} <b class="font-mono text-ink-700">{{ stats.savedAt }}</b></span>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, watch, nextTick, onBeforeUnmount } from 'vue'
import Chart from 'chart.js/auto'
import { RefreshCw, Trash2 } from '@lucide/vue'
import UiButton from '../ui/UiButton.vue'
import { t } from '../../i18n/index.js'
import { useStatsStore } from '../../stores/stats.js'

const stats = useStatsStore()

const RefreshIcon = RefreshCw
const TrashIcon = Trash2

const cards = [
  { key: 'hourly', labelKey: 'stats.today', seconds: 'today_seconds' },
  { key: 'daily', labelKey: 'stats.weeks3', seconds: 'weeks3_seconds' },
  { key: 'monthly', labelKey: 'stats.month', seconds: 'month_seconds' },
  { key: 'yearly', labelKey: 'stats.total', seconds: 'total_seconds', total: true },
]

const canvasRef = ref(null)
const range = ref('daily')
const confirmArmed = ref(false)
let confirmTimer = null
let chart = null

const report = computed(() => stats.report)
const todayDate = computed(() => report.value?.today || '')
const isEmpty = computed(() => !report.value || report.value.empty)

// «X ч Y мин» — формулировки из словаря локали
function fmt(sec) {
  const total = Math.max(0, Math.round(Number(sec) || 0))
  if (total < 60) return total > 0 ? t('stats.timeSec', { n: total }) : t('stats.zeroMin')
  const h = Math.floor(total / 3600)
  const m = Math.round((total % 3600) / 60)
  if (h === 0) return t('stats.timeMin', { n: m })
  return m > 0 ? t('stats.timeHrMin', { h, m }) : t('stats.timeHr', { h })
}

function onResetClick() {
  if (!confirmArmed.value) {
    confirmArmed.value = true
    clearTimeout(confirmTimer)
    confirmTimer = setTimeout(() => (confirmArmed.value = false), 5000)
    return
  }
  clearTimeout(confirmTimer)
  confirmArmed.value = false
  stats.reset()
}

// Будни — синие, выходные — красные (столбцы и подписи оси)
const BAR_WEEKDAY = 'rgba(37, 99, 235, 0.75)'
const BAR_WEEKDAY_HOVER = 'rgba(37, 99, 235, 1)'
const BAR_WEEKEND = 'rgba(220, 68, 68, 0.72)'
const BAR_WEEKEND_HOVER = 'rgba(220, 68, 68, 1)'
const TICK_DEFAULT = '#94a3b8'
const TICK_WEEKEND = '#dc4444'

function renderChart() {
  const canvas = canvasRef.value
  if (!canvas || !canvas.isConnected || canvas.clientWidth === 0) return

  const series = report.value?.series?.[range.value] || []
  const labels = series.map((p) => p.label)
  const seconds = series.map((p) => Math.max(0, Math.round(p.seconds || 0)))

  const isDaily = range.value === 'daily'
  const weekend = series.map((p) => Boolean(p.weekend))
  const barColors = isDaily ? series.map((_, i) => (weekend[i] ? BAR_WEEKEND : BAR_WEEKDAY)) : series.map(() => BAR_WEEKDAY)
  const hoverColors = isDaily ? series.map((_, i) => (weekend[i] ? BAR_WEEKEND_HOVER : BAR_WEEKDAY_HOVER)) : series.map(() => BAR_WEEKDAY_HOVER)
  const tickColors = isDaily ? series.map((_, i) => (weekend[i] ? TICK_WEEKEND : TICK_DEFAULT)) : undefined

  if (chart) {
    chart.data.labels = labels
    chart.data.datasets[0].data = seconds
    chart.data.datasets[0].backgroundColor = barColors
    chart.data.datasets[0].hoverBackgroundColor = hoverColors
    chart.options.scales.x.ticks.color = tickColors
    chart.update()
    return
  }

  chart = new Chart(canvas, {
    type: 'bar',
    data: {
      labels,
      datasets: [{
        label: t('stats.chartLabel'),
        data: seconds,
        backgroundColor: barColors,
        hoverBackgroundColor: hoverColors,
        borderWidth: 0,
        borderRadius: 3,
        maxBarThickness: 42,
      }],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      animation: { duration: 250 },
      plugins: {
        legend: { display: false },
        tooltip: {
          callbacks: {
            label: (ctx) => t('stats.tooltipLabel', { time: fmt(ctx.parsed.y) }),
          },
        },
      },
      scales: {
        x: {
          grid: { display: false },
          ticks: { autoSkip: true, maxRotation: 45, color: tickColors, font: { size: 10 } },
        },
        y: {
          beginAtZero: true,
          grid: { color: 'rgba(100, 116, 139, 0.12)' },
          ticks: {
            font: { size: 10 },
            callback: (v) => {
              const h = Number(v) / 3600
              return h >= 1 ? t('stats.timeHr', { h: Math.round(h * 10) / 10 }) : t('stats.timeMin', { n: Math.round(Number(v) / 60) })
            },
          },
        },
      },
    },
  })
}

watch([range, () => stats.seq], () => {
  nextTick(renderChart)
}, { flush: 'post' })

onBeforeUnmount(() => {
  clearTimeout(confirmTimer)
  if (chart) {
    chart.destroy()
    chart = null
  }
})
</script>
