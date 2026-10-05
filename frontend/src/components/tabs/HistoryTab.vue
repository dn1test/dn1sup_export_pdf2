<template>
  <div class="flex flex-col gap-2">
    <div class="flex items-center gap-2">
      <span class="text-[11px] text-ink-400">{{ t('hist.infoText') }}</span>
      <UiButton
        class="ml-auto"
        size="xs"
        :icon="FolderOpenIcon"
        :disabled="!pdfFolderLink"
        :title="pdfFolderLink ? t('hist.historyPdfTitle') : t('hist.historyNo')"
        @click="openPdfFolder"
      >{{ t('hist.historyPdfBtn') }}</UiButton>
      <UiButton
        size="xs"
        :icon="FolderOpenIcon"
        :disabled="!skpFolderLink"
        :title="skpFolderLink ? t('hist.historySkpTitle') : t('hist.historyNo')"
        @click="openSkpFolder"
      >{{ t('hist.historySkpBtn') }}</UiButton>
      <UiButton size="xs" variant="primary" :icon="PlusIcon" @click="project.addHistoryEntry()">
        {{ t('hist.addBtn') }}
      </UiButton>
    </div>

    <div class="overflow-hidden rounded-lg border border-ink-200 bg-white">
      <table class="w-full border-separate border-spacing-0 text-[13px]">
        <thead>
          <tr class="bg-ink-50 text-left text-[11px] font-medium tracking-wide text-ink-400 uppercase">
            <th class="w-[140px] border-b border-ink-200 px-3 py-1.5">{{ t('hist.thDate') }}</th>
            <th class="w-[95px] border-b border-ink-200 px-3 py-1.5">{{ t('hist.thVerRev') }}</th>
            <th class="border-b border-ink-200 px-3 py-1.5">{{ t('hist.thName') }}</th>
            <th class="w-[80px] border-b border-ink-200 px-3 py-1.5" />
            <th class="w-[80px] border-b border-ink-200 px-3 py-1.5" />
            <th class="w-[60px] border-b border-ink-200 px-3 py-1.5" />
          </tr>
        </thead>
        <tbody>
          <tr v-if="!project.history.length">
            <td colspan="6" class="px-3 py-8 text-center text-ink-400">{{ t('hist.empty') }}</td>
          </tr>
          <tr
            v-for="(h, index) in project.history"
            :key="index + '-' + (h.data || '')"
            class="transition-colors hover:bg-ink-50"
          >
            <td class="border-b border-ink-100 px-3 py-1.5 font-mono text-[11px] text-ink-500" :title="t('hist.dateTitle')">
              {{ h.data || h.date || '' }}
            </td>
            <td
              class="border-b border-ink-100 px-3 py-1.5 font-mono text-[11px] text-ink-500"
              :title="revStr(h) ? t('hist.verRevTitle', { ver: verStr(h), rev: revStr(h) }) : t('hist.revNoRevTitle')"
            >
              {{ verStr(h) || '—' }} # {{ revStr(h) || '—' }}
            </td>
            <td class="border-b border-ink-100 px-3 py-1.5">
              <input
                v-model="h.edit"
                type="text"
                spellcheck="false"
                v-spell
                class="h-7 w-full min-w-0 rounded border border-transparent bg-transparent px-1.5 hover:border-ink-200 focus:border-accent-500 focus:bg-white focus:outline-none"
                :placeholder="t('hist.editPh')"
                @input="onEdit(index, h.edit)"
              >
            </td>
            <td class="border-b border-ink-100 px-3 py-1.5">
              <UiButton
                size="xs"
                :icon="FileTextIcon"
                :disabled="!openable(h)"
                :title="openable(h) ? t('hist.openTitlePdf', { path: h.pdf_link }) : t('hist.openTitleNo')"
                @click="openPdf(h)"
              >{{ t('hist.openPdfBtn') }}</UiButton>
            </td>
            <td class="border-b border-ink-100 px-3 py-1.5">
              <UiButton
                size="xs"
                :icon="FileBoxIcon"
                :disabled="!skpOpenable(h)"
                :title="skpTitle(h)"
                @click="openSkp(h)"
              >{{ t('hist.openSkpBtn') }}</UiButton>
            </td>
            <td class="border-b border-ink-100 px-3 py-1.5">
              <UiButton size="xs" variant="danger" :icon="TrashIcon" :title="t('hist.deleteTitle')" @click="project.removeHistoryEntry(index)">
                {{ t('hist.deleteBtn') }}
              </UiButton>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { Plus, FileText, FileBox, FolderOpen, Trash2 } from '@lucide/vue'
import UiButton from '../ui/UiButton.vue'
import { t } from '../../i18n/index.js'
import { useProjectStore } from '../../stores/project.js'
import { notifyChange } from '../../stores/autosave.js'
import { callRuby } from '../../bridge/sketchup.js'

const project = useProjectStore()

const PlusIcon = Plus
const FileTextIcon = FileText
const FileBoxIcon = FileBox
const FolderOpenIcon = FolderOpen
const TrashIcon = Trash2

function verStr(item) {
  return String(item.ver || '').trim()
}
function revStr(item) {
  return String(item.rev || '').trim()
}
function openable(item) {
  return Boolean(String(item.pdf_link || '').trim())
}
function skpOpenable(item) {
  return Boolean(String(item.skp_link || '').trim()) || (verStr(item) && revStr(item))
}
function skpTitle(item) {
  const link = String(item.skp_link || '').trim()
  if (link) return t('hist.openTitleSkp', { path: link })
  return verStr(item) && revStr(item) ? t('hist.openTitleSkpFind', { ver: verStr(item), rev: revStr(item) }) : t('hist.openTitleSkpNo')
}
function onEdit(index, value) {
  project.syncHistoryEdit(index, value)
  notifyChange()
}
function openPdf(item) {
  const link = String(item.pdf_link || '').trim()
  if (link) callRuby('openFile', link)
}
function openSkp(item) {
  const link = String(item.skp_link || '').trim()
  if (link) {
    callRuby('openFile', link)
  } else if (verStr(item) && revStr(item)) {
    callRuby('openHistorySkp', JSON.stringify({ ver: verStr(item), rev: revStr(item) }))
  }
}

// Папки истории: первая известная ссылка задает папку <Артикул>/pdf или <Артикул>/skp
const pdfFolderLink = computed(() => {
  const found = project.history.find((h) => String(h.pdf_link || '').trim())
  return found ? String(found.pdf_link).trim() : ''
})
const skpFolderLink = computed(() => {
  const found = project.history.find((h) => String(h.skp_link || '').trim())
  return found ? String(found.skp_link).trim() : ''
})
function openPdfFolder() {
  if (pdfFolderLink.value) callRuby('openFolder', pdfFolderLink.value)
}
function openSkpFolder() {
  if (skpFolderLink.value) callRuby('openFolder', skpFolderLink.value)
}
</script>
