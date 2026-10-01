<template>
  <UiModal
    :open="app.articulTypeModal.visible"
    :title="t('articulType.title')"
    :subtitle="t('articulType.subtitle')"
    :icon="HashIcon"
    width="xs"
    @close="app.articulTypeModal.visible = false"
  >
    <p class="text-[13px] text-ink-500">{{ t('articulType.hint') }}</p>
    <template #footer>
      <UiButton @click="app.articulTypeModal.visible = false">{{ t('articulType.later') }}</UiButton>
      <div class="ml-auto flex gap-2">
        <UiButton variant="primary" :icon="UsersIcon" :title="t('articulType.commercialTitle')" @click="app.createProjectArticul(true)">
          {{ t('articulType.commercial') }}
        </UiButton>
        <UiButton variant="success" :icon="UserIcon" :title="t('articulType.householdTitle')" @click="app.createProjectArticul(false)">
          {{ t('articulType.household') }}
        </UiButton>
      </div>
    </template>
  </UiModal>
</template>

<script setup>
import { Hash, Users, User } from '@lucide/vue'
import UiModal from '../ui/UiModal.vue'
import UiButton from '../ui/UiButton.vue'
import { t } from '../../i18n/index.js'
import { useAppStore } from '../../stores/app.js'

const app = useAppStore()
const HashIcon = Hash
const UsersIcon = Users
const UserIcon = User
</script>
