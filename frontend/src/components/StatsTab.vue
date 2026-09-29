<template>
  <div class="stats-tab">
    <div class="stats-toolbar">
      <span class="info-text">
        Статистика активной работы над проектом
        <template v-if="articul"> — <span class="font-mono">{{ articul }}</span></template>
        <template v-if="product"> ({{ product }})</template>:
      </span>
      <span class="stats-toolbar-actions">
        <button type="button" class="btn btn-xs btn-secondary" title="Обновить статистику" @click="legacy('refreshStats')">
          <i class="modus-icons">refresh</i> Обновить
        </button>
        <button
          type="button"
          class="btn btn-xs"
          :class="confirmArmed ? 'btn-danger' : 'btn-secondary'"
          :title="confirmArmed ? 'Нажмите ещё раз для подтверждения' : 'Полностью сбросить статистику этого проекта'"
          @click="onResetClick"
        >
          <i class="modus-icons">delete</i> {{ confirmArmed ? 'Подтвердить сброс?' : 'Сбросить' }}
        </button>
      </span>
    </div>

    <div v-if="statsError" class="stats-error">{{ statsError }}</div>

    <!-- Сводки -->
    <div class="stats-cards">
      <div class="stats-card">
        <span class="stats-card-label">Сегодня</span>
        <span class="stats-card-value">{{ fmt(report?.today_seconds) }}</span>
      </div>
      <div class="stats-card">
        <span class="stats-card-label">7 дней</span>
        <span class="stats-card-value">{{ fmt(report?.week7_seconds) }}</span>
      </div>
      <div class="stats-card">
        <span class="stats-card-label">30 дней</span>
        <span class="stats-card-value">{{ fmt(report?.month30_seconds) }}</span>
      </div>
      <div class="stats-card stats-card-total">
        <span class="stats-card-label">Всего</span>
        <span class="stats-card-value">{{ fmt(report?.total_seconds) }}</span>
      </div>
    </div>

    <!-- График -->
    <div class="stats-chart-panel">
      <div class="stats-range-toggle" role="group" aria-label="Период группировки">
        <button
          v-for="opt in RANGES"
          :key="opt.key"
          type="button"
          class="stats-range-btn"
          :class="{ active: range === opt.key }"
          @click="range = opt.key"
        >{{ opt.label }}</button>
      </div>
      <div class="stats-chart-box">
        <canvas ref="canvasRef"></canvas>
        <div v-if="isEmpty" class="stats-empty">
          Пока нет данных — статистика накапливается во время активной работы в SketchUp
          (моделирование и работа с панелью). Бездействие дольше 5 минут не учитывается.
        </div>
      </div>
    </div>

    <div class="stats-footer" v-if="report && !report.empty">
      <span>Первая активность: <b>{{ report.first_tracked || '—' }}</b></span>
      <span>Последняя активность: <b>{{ report.last_tracked || '—' }}</b></span>
      <span v-if="savedAt">Обновлено: <b>{{ savedAt }}</b></span>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, watch, nextTick, onBeforeUnmount } from 'vue'
import Chart from 'chart.js/auto'
import { ui } from '../store.js'

const RANGES = [
  { key: 'hourly', label: 'Часы' },
  { key: 'daily', label: 'Дни' },
  { key: 'weekly', label: 'Недели' },
  { key: 'monthly', label: 'Месяцы' },
  { key: 'yearly', label: 'Годы' },
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
const isEmpty = computed(() => !report.value || report.value.empty)

function legacy(fn, ...args) {
  window.legacy?.[fn]?.(...args)
}

// «X ч Y мин» / «N мин» / «N сек»
function fmt(sec) {
  const total = Math.max(0, Math.round(Number(sec) || 0))
  if (total < 60) return total > 0 ? `${total} сек` : '0 мин'
  const h = Math.floor(total / 3600)
  const m = Math.round((total % 3600) / 60)
  if (h === 0) return `${m} мин`
  return m > 0 ? `${h} ч ${m} мин` : `${h} ч`
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

function renderChart() {
  const canvas = canvasRef.value
  if (!canvas || !canvas.isConnected || canvas.clientWidth === 0) return

  const series = report.value?.series?.[range.value] || []
  const labels = series.map((p) => p.label)
  const seconds = series.map((p) => Math.max(0, Math.round(p.seconds || 0)))

  if (chart) {
    chart.data.labels = labels
    chart.data.datasets[0].data = seconds
    chart.update()
    return
  }

  chart = new Chart(canvas, {
    type: 'bar',
    data: {
      labels,
      datasets: [{
        label: 'Активная работа',
        data: seconds,
        backgroundColor: 'rgba(0, 94, 176, 0.78)',
        hoverBackgroundColor: 'rgba(0, 94, 176, 1)',
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
            label: (ctx) => ` Работа: ${fmt(ctx.parsed.y)}`,
          },
        },
      },
      scales: {
        x: {
          grid: { display: false },
          ticks: {
            autoSkip: true,
            maxRotation: 45,
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
              return h >= 1 ? `${Math.round(h * 10) / 10} ч` : `${Math.round(Number(v) / 60)} мин`
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
  gap: 12px;
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
  gap: 10px;
}

.stats-card {
  display: flex;
  flex-direction: column;
  gap: 4px;
  padding: 10px 14px;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  background: #f8fafc;
}

.stats-card-label {
  font-size: 12px;
  color: #64748b;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.stats-card-value {
  font-size: 20px;
  font-weight: 600;
  color: #0f172a;
  white-space: nowrap;
}

.stats-card-total {
  background: #eaf2fb;
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

.stats-range-toggle {
  display: inline-flex;
  gap: 2px;
  align-self: flex-start;
  border: 1px solid #e2e8f0;
  border-radius: 6px;
  padding: 2px;
  background: #f8fafc;
}

.stats-range-btn {
  border: none;
  background: transparent;
  padding: 4px 14px;
  font-size: 13px;
  border-radius: 4px;
  cursor: pointer;
  color: #334155;
}

.stats-range-btn:hover {
  background: #eef2f7;
}

.stats-range-btn.active {
  background: #005eb0;
  color: #fff;
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
