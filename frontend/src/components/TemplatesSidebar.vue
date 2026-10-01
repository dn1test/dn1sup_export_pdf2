<template>
  <aside class="templates-sidebar" id="templatesSidebar">
    <div class="templates-sidebar-header">
      <div class="sidebar-title-group">
        <span class="sidebar-title-icon"><i class="modus-icons">dashboard_customize</i></span>
        <span class="sidebar-title-text">{{ t('tsb.title') }}</span>
      </div>
      <div class="sidebar-header-actions">
        <button
          type="button"
          class="btn btn-xs btn-primary btn-add-template"
          :title="t('tsb.newTitle')"
          @click="legacy('openNewTemplateModal')"
        >
          <i class="modus-icons">add_circle</i> {{ t('tsb.newBtn') }}
        </button>
      </div>
    </div>

    <div class="templates-list">
      <div
        v-for="tpl in ui.templates"
        :key="tpl.key"
        class="template-list-item"
        :class="{ active: tpl.active }"
        :title="tpl.sub"
        @click="legacy('selectTemplate', tpl.key)"
      >
        <div class="tpl-item-main">
          <div class="tpl-item-text">
            <span class="tpl-item-name-row">
              <span class="tpl-item-name">{{ tpl.name }}</span>
              <span v-if="tpl.master" class="tpl-master-badge" :title="t('tsb.masterBadgeTitle')">{{ t('tsb.masterBadge') }}</span>
            </span>
            <span class="tpl-item-sub">{{ tpl.sub }}</span>
          </div>
        </div>
        <div class="tpl-item-actions">
          <button
            type="button"
            class="tpl-item-action-btn master-star-btn"
            :class="{ 'master-active': tpl.master }"
            :title="tpl.master ? t('tsb.masterActiveTitle') : t('tsb.masterTitle')"
            :aria-pressed="tpl.master ? 'true' : 'false'"
            @click.stop="legacy('toggleMasterTemplate', tpl.key)"
          >
            <svg class="master-star" viewBox="0 0 24 24" width="14" height="14" aria-hidden="true">
              <path d="M12 2.8l2.85 5.95 6.45.82-4.76 4.5 1.22 6.4L12 17.4l-5.76 3.07 1.22-6.4-4.76-4.5 6.45-.82z" :fill="tpl.master ? 'currentColor' : 'none'" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round" />
            </svg>
          </button>
          <button
            type="button"
            class="tpl-item-action-btn"
            :title="t('tsb.renameTitle')"
            @click.stop="legacy('openRenameTemplateModal', tpl.key)"
          ><i class="modus-icons" style="font-size: 14px">edit</i></button>
          <button
            type="button"
            class="tpl-item-action-btn delete"
            :title="t('tsb.deleteTitle')"
            @click.stop="legacy('openDeleteTemplateModal', tpl.key)"
          ><i class="modus-icons" style="font-size: 14px">delete</i></button>
        </div>
      </div>
    </div>

    <!-- Template Sets: сохранение/загрузка всего списка шаблонов под разные проекты -->
    <div class="templates-sets-section" id="templateSetsSection">
      <div class="templates-sets-header">
        <div class="sidebar-title-group">
          <span class="sidebar-title-icon"><i class="modus-icons">layers</i></span>
          <span class="templates-sets-title">{{ t('tsb.setsTitle') }}</span>
        </div>
        <button
          type="button"
          class="btn btn-xs btn-secondary btn-icon-only"
          :title="t('tsb.saveSetTitle')"
          :aria-label="t('tsb.saveSetAria')"
          @click="legacy('openSaveTemplateSetModal')"
        >
          <i class="modus-icons">save</i>
        </button>
      </div>
      <div class="templates-sets-list">
        <div v-if="!ui.templateSets.length" class="template-set-empty">{{ t('tsb.setsEmpty') }}</div>
        <div
          v-for="set in ui.templateSets"
          :key="set.name"
          class="template-set-item"
          :title="t('tsb.setLoadTitle', { name: set.name })"
          @click="legacy('openConfirmTemplateSetModal', { type: 'load', name: set.name })"
        >
          <div class="tpl-item-text">
            <span class="tpl-item-name">{{ set.name }}</span>
            <span class="tpl-item-sub">{{ set.sub }}</span>
          </div>
          <div class="tpl-item-actions">
            <button
              type="button"
              class="tpl-item-action-btn refresh"
              :title="t('tsb.setRefreshTitle')"
              @click.stop="legacy('openConfirmTemplateSetModal', { type: 'refresh', name: set.name })"
            ><i class="modus-icons" style="font-size: 14px">refresh</i></button>
            <button
              type="button"
              class="tpl-item-action-btn delete"
              :title="t('tsb.setDeleteTitle')"
              @click.stop="legacy('openConfirmTemplateSetModal', { type: 'delete', name: set.name })"
            ><i class="modus-icons" style="font-size: 14px">delete</i></button>
          </div>
        </div>
      </div>
    </div>
  </aside>
</template>

<script setup>
import { ui } from '../store.js'
import { t } from '../i18n/index.js'

function legacy(fn, ...args) {
  window.legacy?.[fn]?.(...args)
}
</script>
