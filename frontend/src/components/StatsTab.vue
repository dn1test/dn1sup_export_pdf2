<template>
  <div class="stats-tab">
    <div class="stats-toolbar">
      <span class="info-text">
        {{ t('stats.infoText') }}
        <template v-if="articul"> — <span class="font-mono">{{ articul }}</span></template>
        <template v-if="product"> ({{ product }})</template>:
      </span>
      <span class="stats-toolbar-actions">
        <button type="button" class="btn btn-xs btn-secondary" :title="t('stats.refreshTitle')" @click="legacy('refreshStats')">
          <i class="modus-icons">refresh</i> {{ t('stats.refreshBtn') }}
        </button>
        <button
          type="button"
          class="btn btn-xs"
          :class="confirmArmed ? 'btn-danger' : 'btn-secondary'"
          :title="confirmArmed ? t('stats.resetConfirmTitle') : t('stats.resetTitle')"
          @click="onResetClick"
        >
          <i class="modus-icons">delete</i> {{ confirmArmed ? t('stats.resetConfirmBtn') : t('stats.resetBtn') }}
        </button>
      </span>
    </div>

    <div v-if="statsError" class="stats-error">{{ statsError }}</div>

    <!-- Сводки: клик по карточке переключает разрез графика -->
    <div class="stats-cards" role="group" :aria-label="t('stats.cardsAria')">
      <button
        v-for="c in cards"
        :key="c.key"
        type="button"
        class="stats-card"
        :class="[{ active: range === c.key }, { 'stats-card-total': c.total }]"
        @click="range = c.key"
      >
        <span class="stats-card-label">
          {{ t(c.labelKey) }}
          <span v-if="c.key === 'hourly' && todayDate" class="stats-card-date">{{ todayDate }}</span>
        </span>
        <span class="stats-card-value">{{ fmt(report?.[c.seconds]) }}</span>
      </button>
    </div>

    <!-- График -->
    <div class="stats-chart-panel">
      <div class="stats-chart-box">
        <canvas ref="canvasRef"></canvas>
        <div v-if="isEmpty" class="stats-empty">
          {{ t('stats.empty') }}
        </div>
      </div>
    </div>

    <div class="stats-footer" v-if="report && !report.empty">
      <span>{{ t('stats.firstActivity') }} <b>{{ report.first_tracked || '—' }}</b></span>
      <span>{{ t('stats.lastActivity') }} <b>{{ report.last_tracked || '—' }}</b></span>
      <span v-if="savedAt">{{ t('stats.updated') }} <b>{{ savedAt }}</b></span>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, watch, nextTick, onBeforeUnmount } from 'vue'
import Chart from 'chart.js/auto'
import { ui } from '../store.js'
import { t } from '../i18n/index.js'

// Карточки-кнопки: клик переключает разрез графика (series из report)
const cards = [
  { key: 'hourly',  labelKey: 'stats.today',  seconds: 'today_seconds' },
  { key: 'daily',   labelKey: 'stats.weeks3', seconds: 'weeks3_seconds' },
  { key: 'monthly', labelKey: 'stats.month',  seconds: 'month_seconds' },
  { key: 'yearly',  labelKey: 'stats.total',  seconds: 'total_seconds', total: true },
]

const canvasRef = ref(null)
const range = ref('daily')
const confirmArmed = ref(false)
let confirmTimer = null
let chart = null

const report = computed(() => ui.stats?.report || null)
const statsError = computed(() => ui.stats?.error || '')
const articul = computed(() => ui.stats?.articul || '')
const product = computed(() => ui.stats?.product || '')
const savedAt = computed(() => ui.stats?.savedAt || '')
const todayDate = computed(() => report.value?.today || '')
const isEmpty = computed(() => !report.value || report.value.empty)

function legacy(fn, ...args) {
  window.legacy?.[fn]?.(...args)
}

// «X ч Y мин» / «N мин» / «N сек» — формулировки берутся из словаря локали
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
    confirmTimer = setTimeout(() => { confirmArmed.value = false }, 5000)
    return
  }
  clearTimeout(confirmTimer)
  confirmArmed.value = false
  legacy('resetStats')
}

// Будни — синие, выходные (сб/вс) — красные: столбцы и подписи на оси
const BAR_WEEKDAY = 'rgba(0, 94, 176, 0.78)'
const BAR_WEEKDAY_HOVER = 'rgba(0, 94, 176, 1)'
const BAR_WEEKEND = 'rgba(214, 69, 69, 0.75)'
const BAR_WEEKEND_HOVER = 'rgba(214, 69, 69, 1)'
const TICK_DEFAULT = '#666666'
const TICK_WEEKEND = '#d64545'

function renderChart() {
  const canvas = canvasRef.value
  if (!canvas || !canvas.isConnected || canvas.clientWidth === 0) return

  const series = report.value?.series?.[range.value] || []
  const labels = series.map((p) => p.label)
  const seconds = series.map((p) => Math.max(0, Math.round(p.seconds || 0)))

  // Разцветка выходных есть только у дневного разреза (daily).
  // Цвета всегда массивами — при смене разреза Chart.js перекрашивает
  // столбцы только если меняется поэлементный набор, строка не срабатывает.
  const isDaily = range.value === 'daily'
  const weekend = series.map((p) => Boolean(p.weekend))
  const barColors = isDaily
    ? series.map((_, i) => (weekend[i] ? BAR_WEEKEND : BAR_WEEKDAY))
    : series.map(() => BAR_WEEKDAY)
  const hoverColors = isDaily
    ? series.map((_, i) => (weekend[i] ? BAR_WEEKEND_HOVER : BAR_WEEKDAY_HOVER))
    : series.map(() => BAR_WEEKDAY_HOVER)
  const tickColors = isDaily
    ? series.map((_, i) => (weekend[i] ? TICK_WEEKEND : TICK_DEFAULT))
    : undefined

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
          ticks: {
            autoSkip: true,
            maxRotation: 45,
            color: tickColors,
            font: { size: 11 },
          },
        },
        y: {
          beginAtZero: true,
          grid: { color: 'rgba(100, 116, 139, 0.15)' },
          ticks: {
            font: { size: 11 },
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

watch([range, () => ui.stats?.seq], () => {
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

<style scoped>
.stats-tab {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 12px 14px;
  height: 100%;
  box-sizing: border-box;
}

.stats-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  flex-wrap: wrap;
}

.stats-toolbar-actions {
  display: inline-flex;
  gap: 6px;
}

.stats-error {
  color: #d32f2f;
  font-size: 13px;
}

.stats-cards {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 8px;
}

.stats-card {
  display: flex;
  flex-direction: column;
  gap: 4px;
  padding: 10px 14px;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  background: #f8fafc;
  cursor: pointer;
  text-align: left;
  font: inherit;
  transition: border-color 0.15s ease, background-color 0.15s ease, box-shadow 0.15s ease;
}

.stats-card:hover {
  border-color: #c5dbf3;
  background: #f1f6fc;
}

.stats-card:focus-visible {
  outline: 2px solid #005eb0;
  outline-offset: 1px;
}

.stats-card.active {
  border-color: #005eb0;
  background: #eaf2fb;
  box-shadow: inset 0 0 0 1px #005eb0;
}

.stats-card-label {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  color: #64748b;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.stats-card-date {
  padding: 1px 6px;
  border-radius: 4px;
  background: #e2e8f0;
  color: #475569;
  font-size: 11px;
  letter-spacing: 0;
  white-space: nowrap;
}

.stats-card-value {
  font-size: 20px;
  font-weight: 600;
  color: #0f172a;
  white-space: nowrap;
}

.stats-card-total {
  border-color: #c5dbf3;
}

.stats-card-total .stats-card-value {
  color: #005eb0;
}

.stats-chart-panel {
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  padding: 10px 12px 12px;
  display: flex;
  flex-direction: column;
  gap: 8px;
  flex: 1;
  min-height: 0;
}

.stats-chart-box {
  position: relative;
  flex: 1;
  min-height: 260px;
}

.stats-empty {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  text-align: center;
  padding: 0 40px;
  color: #64748b;
  font-size: 13px;
}

.stats-footer {
  display: flex;
  gap: 24px;
  flex-wrap: wrap;
  color: #475569;
  font-size: 12px;
}
</style>
