<template>
  <aside class="flex w-60 shrink-0 flex-col border-r border-ink-200 bg-ink-50/60">
    <!-- Список шаблонов -->
    <div class="flex items-center gap-2 px-3 py-2.5">
      <LayoutTemplateIcon :size="14" class="text-ink-400" />
      <span class="text-[13px] font-semibold text-ink-900">{{ t('tsb.title') }}</span>
      <UiButton class="ml-auto" size="xs" variant="primary" :icon="PlusIcon" :title="t('tsb.newTitle')" @click="templates.openNew()">
        {{ t('tsb.newBtn') }}
      </UiButton>
    </div>

    <div class="min-h-0 flex-1 overflow-y-auto px-2 pb-2">
      <div
        v-for="tpl in templates.sidebarList"
        :key="tpl.key"
        class="group mb-1 cursor-pointer rounded-lg border px-2.5 py-2 transition-colors"
        :class="tpl.active
          ? 'border-accent-300 bg-white shadow-card'
          : 'border-transparent hover:border-ink-200 hover:bg-white'"
        :title="tpl.sub"
        @click="templates.select(tpl.key)"
      >
        <div class="flex items-start gap-1.5">
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-1.5">
              <span class="truncate text-[13px] font-medium" :class="tpl.active ? 'text-accent-700' : 'text-ink-900'">{{ tpl.name }}</span>
              <span
                v-if="tpl.master"
                class="inline-flex shrink-0 items-center gap-0.5 rounded bg-amber-50 px-1 py-px text-[9px] font-bold text-amber-600"
                :title="t('tsb.masterBadgeTitle')"
              >
                <StarIcon :size="8" fill="currentColor" />{{ t('tsb.masterBadge') }}
              </span>
            </div>
            <div class="truncate text-[11px] text-ink-400">{{ tpl.sub }}</div>
          </div>
          <div class="flex shrink-0 items-center gap-0.5 opacity-0 transition-opacity group-hover:opacity-100">
            <button
              type="button"
              class="flex size-6 items-center justify-center rounded transition-colors"
              :class="tpl.master ? 'text-amber-500 hover:bg-amber-50' : 'text-ink-300 hover:bg-ink-100 hover:text-amber-500'"
              :title="tpl.master ? t('tsb.masterActiveTitle') : t('tsb.masterTitle')"
              :aria-pressed="tpl.master ? 'true' : 'false'"
              @click.stop="templates.toggleMaster(tpl.key)"
            >
              <StarIcon :size="13" :fill="tpl.master ? 'currentColor' : 'none'" />
            </button>
            <button
              type="button"
              class="flex size-6 items-center justify-center rounded text-ink-300 hover:bg-ink-100 hover:text-ink-600"
              :title="t('tsb.renameTitle')"
              @click.stop="templates.openRename(tpl.key)"
            >
              <PencilIcon :size="12" />
            </button>
            <button
              type="button"
              class="flex size-6 items-center justify-center rounded text-ink-300 hover:bg-red-50 hover:text-red-500"
              :title="t('tsb.deleteTitle')"
              @click.stop="templates.openDelete(tpl.key)"
            >
              <TrashIcon :size="12" />
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Наборы шаблонов -->
    <div class="border-t border-ink-200 px-2 py-2">
      <div class="mb-1 flex items-center gap-2 px-1">
        <LayersIcon :size="13" class="text-ink-400" />
        <span class="text-[11px] font-semibold tracking-wide text-ink-500 uppercase">{{ t('tsb.setsTitle') }}</span>
        <UiButton
          class="ml-auto"
          size="xs"
          variant="ghost"
          :icon="SaveIcon"
          :title="t('tsb.saveSetTitle')"
          :aria-label="t('tsb.saveSetAria')"
          @click="templates.openSaveSet()"
        />
      </div>
      <div class="max-h-40 overflow-y-auto">
        <div v-if="!templates.setsView.length" class="px-2 py-1.5 text-[11px] text-ink-400">{{ t('tsb.setsEmpty') }}</div>
        <div
          v-for="set in templates.setsView"
          :key="set.name"
          class="group mb-0.5 cursor-pointer rounded-md px-2.5 py-1.5 transition-colors hover:bg-white"
          :title="t('tsb.setLoadTitle', { name: set.name })"
          @click="templates.openConfirmSet({ type: 'load', name: set.name })"
        >
          <div class="flex items-center gap-1.5">
            <div class="min-w-0 flex-1">
              <div class="truncate text-xs font-medium text-ink-700">{{ set.name }}</div>
              <div class="truncate text-[10px] text-ink-400">{{ set.sub }}</div>
            </div>
            <div class="flex shrink-0 items-center gap-0.5 opacity-0 group-hover:opacity-100">
              <button
                type="button"
                class="flex size-5 items-center justify-center rounded text-ink-300 hover:bg-ink-100 hover:text-ink-600"
                :title="t('tsb.setRefreshTitle')"
                @click.stop="templates.openConfirmSet({ type: 'refresh', name: set.name })"
              >
                <RefreshIcon :size="11" />
              </button>
              <button
                type="button"
                class="flex size-5 items-center justify-center rounded text-ink-300 hover:bg-red-50 hover:text-red-500"
                :title="t('tsb.setDeleteTitle')"
                @click.stop="templates.openConfirmSet({ type: 'delete', name: set.name })"
              >
                <TrashIcon2 :size="11" />
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </aside>
</template>

<script setup>
import { LayoutTemplate, Plus, Star, Pencil, Trash, Layers, Save, RefreshCw } from '@lucide/vue'
import UiButton from '../ui/UiButton.vue'
import { t } from '../../i18n/index.js'
import { useTemplatesStore } from '../../stores/templates.js'

const templates = useTemplatesStore()

const LayoutTemplateIcon = LayoutTemplate
const PlusIcon = Plus
const StarIcon = Star
const PencilIcon = Pencil
const TrashIcon = Trash
const TrashIcon2 = Trash
const LayersIcon = Layers
const SaveIcon = Save
const RefreshIcon = RefreshCw
</script>
