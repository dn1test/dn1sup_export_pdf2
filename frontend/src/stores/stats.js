// Вкладка «Статистика»: отчёт учёта времени из Ruby (project.yaml → work_stats).
// seq — триггер перерисовки диаграммы при каждом новом отчёте.

import { defineStore } from 'pinia'
import { callRuby } from '../bridge/sketchup.js'
import { notifyChange } from './autosave.js'
import { useProjectStore } from './project.js'

export const useStatsStore = defineStore('stats', {
  state: () => ({
    loaded: false,
    error: '',
    articul: '',
    product: '',
    savedAt: '',
    report: null,
    seq: 0,
  }),

  actions: {
    refresh() {
      callRuby('getWorkStats')
    },
    reset() {
      callRuby('resetWorkStats')
    },
    apply(payload) {
      if (!payload) return
      this.loaded = true
      this.error = payload.error || ''
      this.articul = payload.articul || ''
      this.product = payload.product || ''
      this.savedAt = payload.saved_at || ''
      this.report = payload.report || null
      this.seq++
      // «Общая длительность проекта» (вкладка «Проект»): пустая строка —
      // учет не велся, ручное значение поля не трогаем
      const project = useProjectStore()
      if (typeof payload.total_duration === 'string' && payload.total_duration !== '') {
        project.workflow.total_duration = payload.total_duration
        // Автостоимость: заполняем, только если поле стоимости пустое
        if (project.recalcPrice(false)) notifyChange()
      }
    },
  },
})
