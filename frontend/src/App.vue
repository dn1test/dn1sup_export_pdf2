<template>
  <div class="flex h-screen flex-col overflow-hidden bg-ink-100">
    <AppHeader />

    <!-- Навигация по вкладкам: рабочие вкладки слева, «Настройки» и «Отправка» — группа справа -->
    <nav class="flex shrink-0 items-stretch gap-0.5 overflow-x-auto overflow-y-hidden border-b border-ink-200 bg-white px-2">
      <template v-for="tab in tabs" :key="tab.id">
        <span
          v-if="tab.id === 'tab-settings'"
          class="ml-auto my-1.5 w-px shrink-0 bg-ink-200"
          aria-hidden="true"
        />
        <button
          type="button"
          class="relative flex shrink-0 cursor-pointer items-center gap-1.5 px-3 py-2.5 text-[13px] font-medium whitespace-nowrap transition-colors"
          :class="app.activeTab === tab.id ? 'text-accent-700' : 'text-ink-500 hover:text-ink-800'"
          @click="app.switchTab(tab.id)"
        >
          <component :is="tab.icon" :size="14" />
          {{ t(tab.label) }}
          <span
            v-if="tab.id === 'tab-scenes' && scenes.totalCount"
            class="rounded-full px-1.5 py-px font-mono text-[10px] leading-4"
            :class="app.activeTab === tab.id ? 'bg-accent-100 text-accent-700' : 'bg-ink-100 text-ink-500'"
            :title="t('badge.pagesCount', { active: scenes.activeCount, total: scenes.totalCount })"
          >{{ scenes.activeCount }}</span>
          <span
            v-if="app.activeTab === tab.id"
            class="absolute right-2 bottom-0 left-2 h-0.5 rounded-full bg-accent-600"
          />
        </button>
      </template>
    </nav>

    <!-- Контент вкладок -->
    <main class="min-h-0 flex-1 overflow-hidden">
      <div v-show="app.activeTab === 'tab-project'" class="h-full overflow-y-auto p-3">
        <ProjectTab />
      </div>
      <div v-show="app.activeTab === 'tab-scenes'" class="h-full">
        <ScenesTab />
      </div>
      <div v-show="app.activeTab === 'tab-templates'" class="h-full">
        <TemplatesTab />
      </div>
      <div v-show="app.activeTab === 'tab-directories'" class="h-full overflow-y-auto p-3">
        <DirectoriesTab />
      </div>
      <div v-show="app.activeTab === 'tab-history'" class="h-full overflow-y-auto p-3">
        <HistoryTab />
      </div>
      <div v-show="app.activeTab === 'tab-stats'" class="h-full p-3">
        <StatsTab />
      </div>
      <div v-show="app.activeTab === 'tab-settings'" class="h-full overflow-y-auto p-3">
        <SettingsTab />
      </div>
      <div v-show="app.activeTab === 'tab-send'" class="h-full overflow-y-auto p-3">
        <SendTab />
      </div>
    </main>

    <AppFooter />

    <!-- Глобальные оверлеи и модалки -->
    <AppToast />
    <ProgressOverlay />
    <RevisionModal />
    <ArticulTypeModal />
    <ArticulPromptModal />
    <SuccessModal />
    <ParamModal />
    <TemplateModals />
  </div>
</template>

<script setup>
import { onMounted, onBeforeUnmount } from 'vue'
import {
  ClipboardList, Layers, LayoutTemplate, Folder, History as HistoryIcon,
  BarChart3, Settings as SettingsIcon, Send as SendIcon,
} from '@lucide/vue'
import AppHeader from './components/layout/AppHeader.vue'
import AppFooter from './components/layout/AppFooter.vue'
import AppToast from './components/layout/AppToast.vue'
import ProgressOverlay from './components/layout/ProgressOverlay.vue'
import RevisionModal from './components/modals/RevisionModal.vue'
import ArticulTypeModal from './components/modals/ArticulTypeModal.vue'
import ArticulPromptModal from './components/modals/ArticulPromptModal.vue'
import SuccessModal from './components/modals/SuccessModal.vue'
import ParamModal from './components/modals/ParamModal.vue'
import TemplateModals from './components/modals/TemplateModals.vue'
import ProjectTab from './components/tabs/ProjectTab.vue'
import ScenesTab from './components/tabs/ScenesTab.vue'
import TemplatesTab from './components/tabs/TemplatesTab.vue'
import DirectoriesTab from './components/tabs/DirectoriesTab.vue'
import HistoryTab from './components/tabs/HistoryTab.vue'
import StatsTab from './components/tabs/StatsTab.vue'
import SettingsTab from './components/tabs/SettingsTab.vue'
import SendTab from './components/tabs/SendTab.vue'
import { t } from './i18n/index.js'
import { useAppStore } from './stores/app.js'
import { useScenesStore } from './stores/scenes.js'

const app = useAppStore()
const scenes = useScenesStore()

const tabs = [
  { id: 'tab-project', label: 'tabs.project', icon: ClipboardList },
  { id: 'tab-scenes', label: 'tabs.scenes', icon: Layers },
  { id: 'tab-templates', label: 'tabs.templates', icon: LayoutTemplate },
  { id: 'tab-directories', label: 'tabs.directories', icon: Folder },
  { id: 'tab-history', label: 'tabs.history', icon: HistoryIcon },
  { id: 'tab-stats', label: 'tabs.stats', icon: BarChart3 },
  { id: 'tab-settings', label: 'tabs.settings', icon: SettingsIcon },
  { id: 'tab-send', label: 'tabs.send', icon: SendIcon },
]

// Ctrl+S — сохранить проект (перехватываем до браузерного диалога)
function onKeydown(e) {
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's') {
    e.preventDefault()
    app.forcedSave()
  }
}
onMounted(() => document.addEventListener('keydown', onKeydown))
onBeforeUnmount(() => document.removeEventListener('keydown', onKeydown))
</script>
