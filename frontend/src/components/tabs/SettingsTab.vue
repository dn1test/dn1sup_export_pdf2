<template>
  <div class="flex flex-col gap-3">
    <!-- Параметры LayOut -->
    <UiCard :title="t('set.layoutTitle')">
      <template #icon><LayersIcon :size="14" /></template>
      <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <UiField :label="t('set.renderModeLabel')" :hint="t('set.renderModeHint')">
          <UiSelect v-model="settings.layoutRenderMode" @update:model-value="onAspectSetting">
            <option value="image">{{ t('set.renderModeImage') }}</option>
            <option value="hybrid">{{ t('set.renderModeHybrid') }}</option>
          </UiSelect>
        </UiField>
        <UiField :label="t('set.imageFormatLabel')" :hint="t('set.imageFormatHint')">
          <UiSelect v-model="settings.imageFormat" @update:model-value="notifyChange()">
            <option value="png">{{ t('set.imageFormatPng') }}</option>
            <option value="jpg">{{ t('set.imageFormatJpg') }}</option>
          </UiSelect>
        </UiField>
        <UiField :label="t('set.qualityLabel')" :hint="t('set.qualityHint')">
          <UiSelect v-model="settings.renderQuality" @update:model-value="onAspectSetting">
            <option value="low">{{ t('set.qualityLow') }}</option>
            <option value="medium">{{ t('set.qualityMedium') }}</option>
            <option value="high">{{ t('set.qualityHigh') }}</option>
          </UiSelect>
        </UiField>
        <UiField :label="t('set.scaleLabel')" :hint="t('set.scaleHint')">
          <UiSelect v-model="settings.scaleMultiplier" @update:model-value="onAspectSetting">
            <option value="auto">{{ t('set.scaleAuto') }}</option>
            <option value="0.5">{{ t('set.scale0.5') }}</option>
            <option value="1">{{ t('set.scale1') }}</option>
            <option value="1.5">{{ t('set.scale1.5') }}</option>
            <option value="2.0">{{ t('set.scale2.0') }}</option>
            <option value="2.5">{{ t('set.scale2.5') }}</option>
            <option value="3.0">{{ t('set.scale3.0') }}</option>
          </UiSelect>
        </UiField>
        <div class="flex items-end pb-1">
          <UiCheckbox v-model="settings.saveLayoutFile" :title="t('set.saveLayoutHint')" @update:model-value="notifyChange()">
            {{ t('set.saveLayoutLabel') }}
          </UiCheckbox>
        </div>
      </div>
    </UiCard>

    <!-- Страница и документ -->
    <UiCard :title="t('set.pageTitle')">
      <template #icon><FileIcon :size="14" /></template>
      <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <UiField :label="t('set.pageSizeLabel')">
          <UiSelect v-model="settings.pageSize" @update:model-value="onAspectSetting">
            <option value="A3">{{ t('set.pageSizeA3') }}</option>
          </UiSelect>
        </UiField>
        <UiField :label="t('set.orientLabel')">
          <UiSelect v-model="settings.pageLayout" @update:model-value="onAspectSetting">
            <option value="landscape">{{ t('set.orientLandscape') }}</option>
            <option value="portrait">{{ t('set.orientPortrait') }}</option>
          </UiSelect>
        </UiField>
        <UiField :label="t('set.marginLabel')" :hint="t('set.marginHint')">
          <UiInput
            :model-value="settings.marginMm"
            type="number"
            min="0"
            max="100"
            step="1"
            @update:model-value="settings.marginMm = parseFloat($event) || 0"
            @change="settings.setMargin($event.target.value)"
          />
        </UiField>
        <UiField :label="t('set.fontLabel')" :hint="t('set.fontHint')">
          <UiSelect :model-value="settings.fontFamily" @update:model-value="settings.setFontFamily($event)">
            <option value="Sofia Sans Condensed">Sofia Sans Condensed — {{ t('set.fontStandard') }}</option>
            <option value="Sofia Sans Extra Condensed">Sofia Sans Extra Condensed — {{ t('set.fontExtraCond') }}</option>
            <option value="Oswald">Oswald</option>
            <option value="Roboto Condensed">Roboto Condensed</option>
            <option value="Ubuntu Condensed">Ubuntu Condensed</option>
          </UiSelect>
        </UiField>
        <div class="flex items-end gap-4 pb-1">
          <UiCheckbox v-model="settings.saveSkpBackup" @update:model-value="notifyChange()">
            {{ t('set.backupLabel') }}
          </UiCheckbox>
          <UiCheckbox v-model="settings.antialias" @update:model-value="notifyChange()">
            {{ t('set.antialiasLabel') }}
          </UiCheckbox>
        </div>
      </div>
    </UiCard>

    <!-- Обновление плагина -->
    <UiCard :title="t('set.updateTitle')">
      <template #icon><RefreshIcon :size="14" /></template>
      <template #actions>
        <UiBadge variant="outline" class="font-mono">v{{ app.pluginVersion || '—' }}</UiBadge>
      </template>
      <p class="mb-2 text-[11px] text-ink-400">{{ t('set.updateHint') }}</p>
      <div class="mb-2 flex items-center gap-2 text-[13px]">
        <span>{{ t('set.currentVersion') }} <b class="font-mono">v{{ app.pluginVersion || '—' }}</b></span>
        <span
          v-if="app.update.available"
          class="flex items-center gap-1 rounded bg-amber-50 px-2 py-0.5 text-[11px] font-semibold text-amber-600"
        >
          <DownloadIcon :size="11" /> {{ t('set.newVersionAvailable') }} <b class="font-mono">v{{ app.update.devVersion }}</b>
        </span>
      </div>
      <div class="flex items-center gap-2">
        <UiButton size="sm" :icon="SearchIcon" :title="t('set.checkTitle')" @click="app.checkUpdate()">
          {{ t('set.checkBtn') }}
        </UiButton>
        <UiButton
          size="sm"
          variant="primary"
          :icon="RefreshIcon2"
          :title="t('set.updateBtnTitle')"
          :disabled="!app.update.updateBtnEnabled"
          @click="app.applyUpdate()"
        >
          {{ t('set.updateBtn') }}
        </UiButton>
        <span
          v-if="app.update.status"
          class="min-w-0 flex-1 whitespace-pre-wrap text-[11px] leading-tight"
          :class="{
            'text-accent-600': app.update.kind === 'busy',
            'text-emerald-600': app.update.kind === 'ok',
            'text-amber-600': app.update.kind === 'warn',
            'text-red-500': app.update.kind === 'error',
          }"
        >{{ app.update.status }}</span>
      </div>
    </UiCard>
  </div>
</template>

<script setup>
import { Layers, FileText, RefreshCw, Download, Search } from '@lucide/vue'
import UiCard from '../ui/UiCard.vue'
import UiField from '../ui/UiField.vue'
import UiSelect from '../ui/UiSelect.vue'
import UiInput from '../ui/UiInput.vue'
import UiCheckbox from '../ui/UiCheckbox.vue'
import UiButton from '../ui/UiButton.vue'
import UiBadge from '../ui/UiBadge.vue'
import { t } from '../../i18n/index.js'
import { useAppStore } from '../../stores/app.js'
import { useSettingsStore } from '../../stores/settings.js'
import { notifyChange } from '../../stores/autosave.js'

const app = useAppStore()
const settings = useSettingsStore()

const LayersIcon = Layers
const FileIcon = FileText
const RefreshIcon = RefreshCw
const RefreshIcon2 = RefreshCw
const DownloadIcon = Download
const SearchIcon = Search

// Смена настройки, влияющей на оверлей кадра: толкаем в SketchUp + автосейв
function onAspectSetting() {
  settings.aspectChanged()
}
</script>
