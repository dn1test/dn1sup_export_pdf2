<template>
<!-- Разметка перенесена из App.vue (Фаза 3). Все id сохранены: legacy читает и пишет
     значения контролов напрямую (els map), поэтому биндинги v-model не нужны.
     Тексты — через t() из i18n: смена локали перерисовывает карточки реактивно. -->
<div class="tab-stack">
        <!-- LayOut Parameters Card -->
        <div class="settings-card">
          <div class="card-header">
            <span class="card-header-icon"><i class="modus-icons">layers</i></span>
            <span class="card-header-title">{{ t('set.layoutTitle') }}</span>
          </div>
          <div class="form-grid">
            <div class="form-group" id="layoutRenderModeGroup">
              <label for="selectLayoutRenderMode">{{ t('set.renderModeLabel') }}</label>
              <select id="selectLayoutRenderMode" class="form-control">
                <option value="image" selected>{{ t('set.renderModeImage') }}</option>
                <option value="hybrid">{{ t('set.renderModeHybrid') }}</option>
              </select>
              <span class="field-hint">{{ t('set.renderModeHint') }}</span>
            </div>

            <div class="form-group" id="compressionGroup" style="display: none;">
              <select id="selectCompression" class="form-control">
                <option value="compress" selected>{{ t('set.compressOn') }}</option>
                <option value="none">{{ t('set.compressOff') }}</option>
              </select>
            </div>

            <div class="form-group" id="imageFormatGroup">
              <label for="selectImageFormat">{{ t('set.imageFormatLabel') }}</label>
              <select id="selectImageFormat" class="form-control">
                <option value="png" selected>{{ t('set.imageFormatPng') }}</option>
                <option value="jpg">{{ t('set.imageFormatJpg') }}</option>
              </select>
              <span class="field-hint">{{ t('set.imageFormatHint') }}</span>
            </div>

            <div class="form-group" id="qualityGroup">
              <label for="selectQuality">{{ t('set.qualityLabel') }}</label>
              <select id="selectQuality" class="form-control">
                <option value="low">{{ t('set.qualityLow') }}</option>
                <option value="medium" selected>{{ t('set.qualityMedium') }}</option>
                <option value="high">{{ t('set.qualityHigh') }}</option>
              </select>
              <span class="field-hint">{{ t('set.qualityHint') }}</span>
            </div>

            <div class="form-group" id="scaleMultiplierGroup">
              <label for="selectScaleMultiplier">{{ t('set.scaleLabel') }}</label>
              <select id="selectScaleMultiplier" class="form-control">
                <option value="auto">{{ t('set.scaleAuto') }}</option>
                <option value="0.5">{{ t('set.scale0.5') }}</option>
                <option value="1">{{ t('set.scale1') }}</option>
                <option value="1.5">{{ t('set.scale1.5') }}</option>
                <option value="2.0" selected>{{ t('set.scale2.0') }}</option>
                <option value="2.5">{{ t('set.scale2.5') }}</option>
                <option value="3.0">{{ t('set.scale3.0') }}</option>
              </select>
              <span class="field-hint">{{ t('set.scaleHint') }}</span>
            </div>


            <div class="form-group" id="layoutSaveFileGroup">
              <label class="checkbox-label">
                <input type="checkbox" id="chkSaveLayoutFile" checked>
                <span>{{ t('set.saveLayoutLabel') }}</span>
              </label>
              <span class="field-hint">{{ t('set.saveLayoutHint') }}</span>
            </div>
          </div>
        </div>

        <!-- Page and Document Parameters Card -->
        <div class="settings-card">
          <div class="card-header">
            <span class="card-header-icon"><i class="modus-icons">file</i></span>
            <span class="card-header-title">{{ t('set.pageTitle') }}</span>
          </div>
          <div class="form-grid">
            <div class="form-group">
              <label for="selectPageSize">{{ t('set.pageSizeLabel') }}</label>
              <select id="selectPageSize" class="form-control">
                <option value="A3" selected>{{ t('set.pageSizeA3') }}</option>
              </select>
            </div>

            <div class="form-group">
              <label for="selectPageLayout">{{ t('set.orientLabel') }}</label>
              <select id="selectPageLayout" class="form-control">
                <option value="landscape">{{ t('set.orientLandscape') }}</option>
                <option value="portrait">{{ t('set.orientPortrait') }}</option>
              </select>
            </div>

            <div class="form-group">
              <label for="inputPageMargin">{{ t('set.marginLabel') }}</label>
              <input type="number" id="inputPageMargin" class="form-control" min="0" max="100" step="1" value="5">
              <span class="field-hint">{{ t('set.marginHint') }}</span>
            </div>

            <div class="form-group" id="fontFamilyGroup">
              <label for="selectFontFamily">{{ t('set.fontLabel') }}</label>
              <select id="selectFontFamily" class="form-control">
                <option value="Sofia Sans Condensed" selected>Sofia Sans Condensed {{ t('set.fontStandard') }}</option>
                <option value="Sofia Sans Extra Condensed">Sofia Sans Extra Condensed {{ t('set.fontExtraCond') }}</option>
                <option value="Oswald">Oswald</option>
                <option value="Roboto Condensed">Roboto Condensed</option>
                <option value="Ubuntu Condensed">Ubuntu Condensed</option>
              </select>
              <span class="field-hint">{{ t('set.fontHint') }}</span>
            </div>

            <div class="form-group full-width">
              <div class="checkbox-group">
                <label class="checkbox-label">
                  <input type="checkbox" id="chkSaveBackup" checked>
                  <span>{{ t('set.backupLabel') }}</span>
                </label>
                <label class="checkbox-label">
                  <input type="checkbox" id="chkAntialias" checked>
                  <span>{{ t('set.antialiasLabel') }}</span>
                </label>
              </div>
            </div>
          </div>
        </div>

        <!-- Section: Обновление плагина (путь к dev-папке резолвится в Ruby, в GUI не показывается) -->
        <div class="settings-card" id="cardPluginUpdate">
          <div class="card-header">
            <div class="card-header-title-wrap">
              <span class="card-header-icon"><i class="modus-icons">autorenew</i></span>
              <span class="card-header-title">{{ t('set.updateTitle') }}</span>
            </div>
            <span class="badge-dev-version" id="badgeDevVersion" style="font-weight: 600; padding: 2px 7px; border-radius: 4px; background: rgba(0,0,0,0.06); font-size: 11px;">v2.6.0</span>
          </div>
          <p class="field-hint">{{ t('set.updateHint') }}</p>
          <div class="form-group" style="margin-bottom: 8px;">
            <div style="display: flex; align-items: center; gap: 6px; min-height: 18px;">
              <span>{{ t('set.currentVersion') }} <b id="curVersionText">v2.6.0</b></span>
            </div>
            <div id="updateAvailableRow" style="display: none; align-items: center; gap: 6px; margin-top: 4px; color: var(--bs-warning); font-weight: 600;">
              <i class="modus-icons">download</i> {{ t('set.newVersionAvailable') }} <b id="newVersionText"></b>
            </div>
          </div>
          <div style="display: flex; gap: 8px;">
            <button type="button" class="btn btn-xs btn-secondary" id="btnCheckUpdate" :title="t('set.checkTitle')"><i class="modus-icons">search</i> {{ t('set.checkBtn') }}</button>
            <button type="button" class="btn btn-xs btn-primary" id="btnUpdate" :title="t('set.updateBtnTitle')" disabled><i class="modus-icons">autorenew</i> {{ t('set.updateBtn') }}</button>
          </div>
          <div id="devUpdateStatus" class="field-hint" style="font-size: 11px; margin-top: 4px; min-height: 16px;"></div>
        </div>
</div>
</template>

<script setup>
import { t } from '../i18n/index.js'
</script>
