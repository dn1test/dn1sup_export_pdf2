<template>
  <header class="flex shrink-0 items-center gap-3 border-b border-ink-200 bg-white px-3.5 py-2">
    <!-- Бренд -->
    <div class="flex items-center gap-2.5">
      <div
        class="flex h-8 w-8 items-center justify-center rounded-lg bg-accent-600 text-white"
        :title="t('app.versionBadgeTitle', { version: app.pluginVersion || '—' })"
      >
        <FileTextIcon :size="16" />
      </div>
      <div class="leading-tight">
        <div class="text-[13px] font-semibold text-ink-900">export PDF</div>
        <div class="font-mono text-[10px] text-ink-400">v{{ app.pluginVersion || '…' }}</div>
      </div>
    </div>

    <div class="mx-2 h-8 w-px bg-ink-200" />

    <!-- Проект: изделие / помещение — адрес / заказчик или компания -->
    <div class="min-w-0 flex-1 leading-tight">
      <div
        class="truncate text-[20px] font-medium"
        :class="project.headerProduct.real ? 'text-ink-900' : 'text-ink-400'"
        :title="project.headerProduct.text"
      >{{ project.headerProduct.text }}</div>
      <div
        class="truncate text-[18px]"
        :class="project.headerPlaceAdress.real ? 'text-ink-500' : 'text-ink-400'"
        :title="project.headerPlaceAdress.text"
      >{{ project.headerPlaceAdress.text }}</div>
      <div
        class="truncate text-[18px]"
        :class="project.headerClient.real ? 'text-ink-500' : 'text-ink-400'"
        :title="project.headerClient.text"
      >{{ project.headerClient.text }}</div>
    </div>

    <!-- Правый столбец: язык в верхнем углу, под ним артикул -->
    <div class="flex shrink-0 flex-col items-end gap-1.5">
      <!-- Язык RU|EN -->
      <div class="flex items-center gap-1.5" :title="t('app.languageTitle')">
        <GlobeIcon :size="14" class="text-ink-400" />
        <div class="flex rounded-md border border-ink-200 p-0.5" role="group" :aria-label="t('app.languageTitle')">
          <button
            v-for="lang in ['ru', 'en']"
            :key="lang"
            type="button"
            class="rounded px-2 py-0.5 text-[11px] font-semibold uppercase transition-colors"
            :class="locale === lang ? 'bg-accent-600 text-white' : 'text-ink-500 hover:text-ink-700'"
            :aria-pressed="locale === lang"
            @click="app.setLanguage(lang)"
          >{{ lang }}</button>
        </div>
      </div>

      <!-- Артикул -->
      <div class="flex items-center gap-2 rounded-md border border-ink-200 bg-ink-50 px-2.5 py-1" :title="t('app.articulTitle')">
        <span class="font-mono text-[13px] font-medium text-ink-900">{{ project.articulValue || '—' }}</span>
        <span
          v-if="project.articulValue"
          class="inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-[10px] font-semibold"
          :class="project.isCommercial ? 'bg-accent-100 text-accent-700' : 'bg-emerald-50 text-emerald-700'"
          :title="t('app.tradeTitle')"
        >
          <component :is="project.isCommercial ? UsersIcon : UserIcon" :size="11" />
          {{ project.isCommercial ? t('app.tradeCommercial') : t('app.tradeHousehold') }}
        </span>
        <span v-else class="text-[10px] text-ink-400">{{ t('app.tradeUnset') }}</span>
      </div>
    </div>
  </header>
</template>

<script setup>
import { FileText, Globe, Hash, User, Users } from '@lucide/vue'
import { t, locale } from '../../i18n/index.js'
import { useAppStore } from '../../stores/app.js'
import { useProjectStore } from '../../stores/project.js'

const app = useAppStore()
const project = useProjectStore()
const FileTextIcon = FileText
const GlobeIcon = Globe
const HashIcon = Hash
const UsersIcon = Users
const UserIcon = User
</script>
