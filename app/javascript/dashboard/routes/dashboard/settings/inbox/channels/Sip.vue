<script setup>
import { reactive, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';

import PageHeader from '../../SettingsSubPageHeader.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const store = useStore();
const router = useRouter();

const state = reactive({
  name: '',
  url: '',
  phoneNumber: '',
});

const uiFlags = useMapGetter('inboxes/getUIFlags');

const isWebSocketUrl = value => /^wss?:\/\/\S+$/.test(value);

const validationRules = {
  name: { required },
  url: { required, isWebSocketUrl },
};

const v$ = useVuelidate(validationRules, state);
const isSubmitDisabled = computed(() => v$.value.$invalid);

const formErrors = computed(() => ({
  name: v$.value.name?.$error ? t('INBOX_MGMT.ADD.SIP.NAME.ERROR') : '',
  url: v$.value.url?.$error ? t('INBOX_MGMT.ADD.SIP.URL.ERROR') : '',
}));

async function createChannel() {
  const isFormValid = await v$.value.$validate();
  if (!isFormValid) return;

  try {
    const channel = await store.dispatch('inboxes/createVoiceChannel', {
      name: state.name,
      voice: {
        provider: 'sip',
        url: state.url,
        phone_number: state.phoneNumber,
      },
    });

    router.replace({
      name: 'settings_inboxes_add_agents',
      params: { page: 'new', inbox_id: channel.id },
    });
  } catch (error) {
    useAlert(
      error.response?.data?.message || t('INBOX_MGMT.ADD.SIP.API.ERROR_MESSAGE')
    );
  }
}
</script>

<template>
  <div class="overflow-auto col-span-6 p-6 w-full h-full">
    <PageHeader
      :header-title="t('INBOX_MGMT.ADD.SIP.TITLE')"
      :header-content="t('INBOX_MGMT.ADD.SIP.DESC')"
    />

    <form
      class="flex flex-col gap-4 flex-wrap mx-0"
      @submit.prevent="createChannel"
    >
      <Input
        v-model="state.name"
        :label="t('INBOX_MGMT.ADD.SIP.NAME.LABEL')"
        :placeholder="t('INBOX_MGMT.ADD.SIP.NAME.PLACEHOLDER')"
        :message="formErrors.name"
        :message-type="formErrors.name ? 'error' : 'info'"
        @blur="v$.name?.$touch"
      />

      <Input
        v-model="state.url"
        :label="t('INBOX_MGMT.ADD.SIP.URL.LABEL')"
        :placeholder="t('INBOX_MGMT.ADD.SIP.URL.PLACEHOLDER')"
        :message="formErrors.url"
        :message-type="formErrors.url ? 'error' : 'info'"
        @blur="v$.url?.$touch"
      />

      <Input
        v-model="state.phoneNumber"
        :label="t('INBOX_MGMT.ADD.SIP.PHONE_NUMBER.LABEL')"
        :placeholder="t('INBOX_MGMT.ADD.SIP.PHONE_NUMBER.PLACEHOLDER')"
      />

      <div>
        <NextButton
          :is-loading="uiFlags.isCreating"
          :disabled="isSubmitDisabled"
          :label="t('INBOX_MGMT.ADD.SIP.SUBMIT_BUTTON')"
          type="submit"
        />
      </div>
    </form>
  </div>
</template>
