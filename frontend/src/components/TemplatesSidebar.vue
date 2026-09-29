<template>
  <aside class="templates-sidebar" id="templatesSidebar">
    <div class="templates-sidebar-header">
      <div class="sidebar-title-group">
        <span class="sidebar-title-icon"><i class="modus-icons">dashboard_customize</i></span>
        <span class="sidebar-title-text">Название шаблона</span>
      </div>
      <div class="sidebar-header-actions">
        <button
          type="button"
          class="btn btn-xs btn-primary btn-add-template"
          title="Создать новый пользовательский шаблон страницы"
          @click="legacy('openNewTemplateModal')"
        >
          <i class="modus-icons">add_circle</i> Новый
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
            <span class="tpl-item-name">{{ tpl.name }}</span>
            <span class="tpl-item-sub">{{ tpl.sub }}</span>
          </div>
        </div>
        <div class="tpl-item-actions">
          <button
            type="button"
            class="tpl-item-action-btn"
            title="Переименовать шаблон"
            @click.stop="legacy('openRenameTemplateModal', tpl.key)"
          ><i class="modus-icons" style="font-size: 14px">edit</i></button>
          <button
            type="button"
            class="tpl-item-action-btn delete"
            title="Удалить шаблон"
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
          <span class="templates-sets-title">Наборы шаблонов</span>
        </div>
        <button
          type="button"
          class="btn btn-xs btn-secondary btn-icon-only"
          title="Сохранить текущий список шаблонов как набор для быстрого переключения между проектами"
          aria-label="Сохранить набор"
          @click="legacy('openSaveTemplateSetModal')"
        >
          <i class="modus-icons">save</i>
        </button>
      </div>
      <div class="templates-sets-list">
        <div v-if="!ui.templateSets.length" class="template-set-empty">Нет сохраненных наборов</div>
        <div
          v-for="set in ui.templateSets"
          :key="set.name"
          class="template-set-item"
          :title="`Загрузить набор «${set.name}» (текущие шаблоны будут заменены)`"
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
              title="Обновить набор: перезаписать его текущим списком шаблонов"
              @click.stop="legacy('openConfirmTemplateSetModal', { type: 'refresh', name: set.name })"
            ><i class="modus-icons" style="font-size: 14px">refresh</i></button>
            <button
              type="button"
              class="tpl-item-action-btn delete"
              title="Удалить набор"
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

function legacy(fn, ...args) {
  window.legacy?.[fn]?.(...args)
}
</script>
