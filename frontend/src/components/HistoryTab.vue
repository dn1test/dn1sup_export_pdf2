<template>
  <div>
    <div class="history-toolbar">
      <span class="info-text">{{ t('hist.infoText') }}</span>
      <button type="button" class="btn btn-xs btn-primary" @click="legacy('addHistoryEntry')">
        <i class="modus-icons">add_circle</i> {{ t('hist.addBtn') }}
      </button>
    </div>

    <div class="table-container">
      <table class="history-table">
        <thead>
          <tr>
            <th width="140">{{ t('hist.thDate') }}</th>
            <th width="95">{{ t('hist.thVerRev') }}</th>
            <th>{{ t('hist.thName') }}</th>
            <th width="85">{{ t('hist.thOpen') }}</th>
            <th width="85">{{ t('hist.thDelete') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="!ui.history.length">
            <td colspan="5" class="dir-empty-state" style="text-align: center">
              {{ t('hist.empty') }}
            </td>
          </tr>
          <tr v-for="(h, index) in ui.history" :key="h.uid">
            <!-- 1. Дата и время — только чтение, проставляется автоматически -->
            <td class="history-date-cell font-mono" :title="t('hist.dateTitle')">
              {{ h.item.data || h.item.date || '' }}
            </td>
            <!-- 2. Версия # Ревизия — только чтение -->
            <td
              class="history-rev-cell font-mono"
              :title="revStr(h.item) ? t('hist.verRevTitle', { ver: verStr(h.item), rev: revStr(h.item) }) : t('hist.revNoRevTitle')"
            >{{ verStr(h.item) || '—' }} # {{ revStr(h.item) || '—' }}</td>
            <!-- 3. Название правки (edit/text/description пишутся синхронно) -->
            <td>
              <input
                v-model="h.item.edit"
                type="text"
                class="table-input"
                :placeholder="t('hist.editPh')"
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
                :title="(h.item.pdf_link || '').trim() ? t('hist.openTitlePdf', { path: h.item.pdf_link }) : t('hist.openTitleNo')"
                @click="openPdf(h.item)"
              ><i class="modus-icons">launch</i> {{ t('hist.openBtn') }}</button>
            </td>
            <!-- 5. Удаление -->
            <td class="history-action-cell">
              <button type="button" class="btn btn-xs btn-danger" :title="t('hist.deleteTitle')" @click="legacy('removeHistoryEntry', index)">
                <i class="modus-icons">delete</i> {{ t('hist.deleteBtn') }}
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
import { t } from '../i18n/index.js'

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
