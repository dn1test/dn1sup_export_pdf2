<template>
  <div>
    <div class="history-toolbar">
      <span class="info-text">Журнал изменений проекта (workflow.history_edit):</span>
      <button type="button" class="btn btn-xs btn-primary" @click="legacy('addHistoryEntry')">
        <i class="modus-icons">add_circle</i> Добавить правку
      </button>
    </div>

    <div class="table-container">
      <table class="history-table">
        <thead>
          <tr>
            <th width="140">Дата и время</th>
            <th width="95">Версия # Ревизия</th>
            <th>Название правки</th>
            <th width="85">Открыть</th>
            <th width="85">Удалить</th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="!ui.history.length">
            <td colspan="5" class="dir-empty-state" style="text-align: center">
              Записей пока нет — добавьте первую правку кнопкой выше.
            </td>
          </tr>
          <tr v-for="(h, index) in ui.history" :key="h.uid">
            <!-- 1. Дата и время — только чтение, проставляется автоматически -->
            <td class="history-date-cell font-mono" title="Дата и время проставляются автоматически">
              {{ h.item.data || h.item.date || '' }}
            </td>
            <!-- 2. Версия # Ревизия — только чтение -->
            <td
              class="history-rev-cell font-mono"
              :title="revStr(h.item) ? `Версия ${verStr(h.item)} # Ревизия ${revStr(h.item)}` : 'Ревизия не назначена (запись без экспорта)'"
            >{{ verStr(h.item) || '—' }} # {{ revStr(h.item) || '—' }}</td>
            <!-- 3. Название правки (edit/text/description пишутся синхронно) -->
            <td>
              <input
                v-model="h.item.edit"
                type="text"
                class="table-input"
                placeholder="Текст правки / комментарий..."
                @input="legacy('syncHistoryEdit', index, h.item.edit)"
                @change="legacy('notifyChange')"
              >
            </td>
            <!-- 4. Открыть привязанный PDF -->
            <td class="history-action-cell">
              <button
                type="button"
                class="btn btn-xs btn-secondary"
                :disabled="!(h.item.pdf_link || '').trim()"
                :title="(h.item.pdf_link || '').trim() ? `Открыть PDF: ${h.item.pdf_link}` : 'PDF ещё не создан для этой правки'"
                @click="openPdf(h.item)"
              ><i class="modus-icons">launch</i> Открыть</button>
            </td>
            <!-- 5. Удаление -->
            <td class="history-action-cell">
              <button type="button" class="btn btn-xs btn-danger" title="Удалить запись" @click="legacy('removeHistoryEntry', index)">
                <i class="modus-icons">delete</i> Удалить
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<script setup>
import { ui } from '../store.js'

function legacy(fn, ...args) {
  window.legacy?.[fn]?.(...args)
}
function verStr(item) {
  return String(item.ver || '').trim()
}
function revStr(item) {
  return String(item.rev || '').trim()
}
function openPdf(item) {
  const link = (item.pdf_link || '').trim()
  if (link) window.legacy?.callRuby?.('openFile', link)
}
</script>
