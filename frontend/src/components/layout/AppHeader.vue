<template>
  <header class="flex shrink-0 items-center gap-3 border-b border-ink-200 bg-white px-3.5 py-2">
    <!-- Бренд -->
    <div class="flex items-center gap-2.5">
      <img
        src="../../assets/logo.svg"
        width="32"
        height="32"
        class="shrink-0"
        :title="t('app.versionBadgeTitle', { version: app.pluginVersion || '—' })"
        alt="DN1Sup Export PDF 2"
      >
      <div class="leading-tight">
        <div class="text-[13px] font-semibold text-ink-900">export PDF</div>
        <div class="flex items-center gap-1.5">
          <span class="font-mono text-[10px] text-ink-400">v{{ app.pluginVersion || '…' }}</span>
        </div>
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
      <div class="flex items-center gap-1">
        <!-- Проверить обновление — только с GitHub, процесс виден спиннером и тостами -->
        <button
          type="button"
          class="rounded-full p-1.5 text-ink-400 transition-colors hover:bg-ink-50 hover:text-accent-600 disabled:opacity-50"
          :title="updateBtnTitle"
          :disabled="app.updateStatus.checking"
          @click="app.checkUpdateFull()"
        >
          <RefreshIcon :size="16" :class="{ 'animate-spin': app.updateStatus.checking }" />
        </button>
        <!-- Справка: как пользоваться расширением -->
        <button
          type="button"
          class="rounded-full p-1.5 text-ink-400 transition-colors hover:bg-ink-50 hover:text-accent-600"
          :title="t('app.helpTitle')"
          @click="$emit('open-help')"
        >
          <HelpIcon :size="16" />
        </button>
        <!-- Светлая / тёмная тема -->
        <button
          type="button"
          class="rounded-full p-1.5 text-ink-400 transition-colors hover:bg-ink-50 hover:text-accent-600"
          :title="isDark ? t('theme.toLight') : t('theme.toDark')"
          @click="toggleTheme()"
        >
          <component :is="isDark ? SunIcon : MoonIcon" :size="16" />
        </button>
        <!-- Язык: одна кнопка с глобусом, показывает ЦЕЛЕВОЙ язык -->
        <button
          type="button"
          class="flex items-center gap-1 rounded-md border border-ink-200 px-2 py-0.5 text-[11px] font-semibold uppercase text-ink-500 transition-colors hover:text-ink-700"
          :title="locale === 'ru' ? t('app.languageToEn') : t('app.languageToRu')"
          :aria-label="locale === 'ru' ? t('app.languageToEn') : t('app.languageToRu')"
          :aria-pressed="false"
          @click="app.setLanguage(locale === 'ru' ? 'en' : 'ru')"
        >
          <GlobeIcon :size="14" class="text-ink-400" />
          {{ locale === 'ru' ? 'EN' : 'RU' }}
        </button>
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
import { Globe, Hash, HelpCircle, Moon, RotateCw, Sun, User, Users } from '@lucide/vue'
import { computed } from 'vue'
import { t, locale } from '../../i18n/index.js'
import { useAppStore } from '../../stores/app.js'
import { useProjectStore } from '../../stores/project.js'
import { useTheme } from '../../composables/useTheme.js'

defineEmits(['open-help'])

const app = useAppStore()
const project = useProjectStore()
const { isDark, toggleTheme } = useTheme()
// Тултип кнопки обновления: во время проверки показывает живой этап/процент
const updateBtnTitle = computed(() => {
  const st = app.updateStatus
  if (st && st.checking) {
    if (st.stage === 'downloading') return t('toast.updateDownloading', { pct: st.percent })
    if (st.stage === 'installing') return t('toast.updateInstalling')
    if (st.stage === 'found') return t('toast.updateFound', { cur: app.pluginVersion || '…', dev: '' })
    return t('toast.checkingUpdate')
  }
  return t('app.checkUpdateTitle')
})
const GlobeIcon = Globe
const HashIcon = Hash
const UsersIcon = Users
const UserIcon = User
const RefreshIcon = RotateCw
const HelpIcon = HelpCircle
const SunIcon = Sun
const MoonIcon = Moon
</script>
