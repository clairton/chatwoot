<script setup>
import { onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import InboxesAPI from 'dashboard/api/inboxes';
import SipExtensionsAPI from 'dashboard/api/channel/sip/sipExtensionsAPI';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import NextInput from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  inbox: {
    type: Object,
    default: () => ({}),
  },
});

const { t } = useI18n();
const store = useStore();

const pbx = reactive({
  url: props.inbox.url || '',
  phoneNumber: props.inbox.phone_number || '',
});
const isUpdatingPbx = ref(false);
const inboundCallsEnabled = ref(props.inbox.inbound_calls_enabled !== false);
const isTogglingInbound = ref(false);
// One editable row per inbox member; the password is write-only, so it starts
// empty and an empty value keeps the saved one.
const extensions = ref([]);
const savingUserId = ref(null);

watch(
  () => props.inbox.inbound_calls_enabled,
  value => {
    inboundCallsEnabled.value = value !== false;
  }
);

const fetchExtensions = async () => {
  const payload = await SipExtensionsAPI.list(props.inbox.id);
  extensions.value = payload.map(extension => ({
    userId: extension.user_id,
    name: extension.name,
    thumbnail: extension.thumbnail,
    sipUri: extension.sip_uri || '',
    sipPassword: '',
    hasPassword: extension.has_password,
  }));
};

onMounted(fetchExtensions);

const updatePbx = async () => {
  isUpdatingPbx.value = true;
  try {
    await store.dispatch('inboxes/updateInbox', {
      id: props.inbox.id,
      formData: false,
      channel: { url: pbx.url, phone_number: pbx.phoneNumber },
    });
    useAlert(t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
  } catch (_) {
    useAlert(t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
  } finally {
    isUpdatingPbx.value = false;
  }
};

const toggleInboundCalls = async value => {
  if (isTogglingInbound.value) return;
  const previousValue = inboundCallsEnabled.value;
  inboundCallsEnabled.value = value;
  isTogglingInbound.value = true;
  try {
    await InboxesAPI.setInboundCalls(props.inbox.id, value);
    await store.dispatch('inboxes/get', props.inbox.id);
    useAlert(t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
  } catch (_) {
    inboundCallsEnabled.value = previousValue;
    useAlert(t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
  } finally {
    isTogglingInbound.value = false;
  }
};

const saveExtension = async extension => {
  savingUserId.value = extension.userId;
  try {
    const saved = await SipExtensionsAPI.save(
      props.inbox.id,
      extension.userId,
      {
        sipUri: extension.sipUri,
        sipPassword: extension.sipPassword,
      }
    );
    extension.sipPassword = '';
    extension.hasPassword = saved.has_password;
    useAlert(t('INBOX_MGMT.SIP_CONFIGURATION.EXTENSIONS.SUCCESS_MESSAGE'));
  } catch (_) {
    useAlert(t('INBOX_MGMT.SIP_CONFIGURATION.EXTENSIONS.ERROR_MESSAGE'));
  } finally {
    savingUserId.value = null;
  }
};
</script>

<template>
  <div class="flex flex-col gap-6">
    <div>
      <SettingsFieldSection :label="$t('INBOX_MGMT.ADD.SIP.URL.LABEL')">
        <NextInput
          v-model="pbx.url"
          :placeholder="$t('INBOX_MGMT.ADD.SIP.URL.PLACEHOLDER')"
        />
      </SettingsFieldSection>
      <SettingsFieldSection
        :label="$t('INBOX_MGMT.ADD.SIP.PHONE_NUMBER.LABEL')"
      >
        <NextInput
          v-model="pbx.phoneNumber"
          :placeholder="$t('INBOX_MGMT.ADD.SIP.PHONE_NUMBER.PLACEHOLDER')"
        />
      </SettingsFieldSection>
      <NextButton
        :is-loading="isUpdatingPbx"
        :disabled="!pbx.url"
        :label="$t('INBOX_MGMT.SETTINGS_POPUP.UPDATE')"
        @click="updatePbx"
      />
    </div>

    <SettingsToggleSection
      :model-value="inboundCallsEnabled"
      :header="$t('INBOX_MGMT.VOICE_CONFIGURATION.INBOUND.LABEL')"
      :description="$t('INBOX_MGMT.VOICE_CONFIGURATION.INBOUND.DESCRIPTION')"
      @update:model-value="toggleInboundCalls"
    />

    <SettingsFieldSection
      :label="$t('INBOX_MGMT.SIP_CONFIGURATION.WEBHOOK.LABEL')"
      :help-text="$t('INBOX_MGMT.SIP_CONFIGURATION.WEBHOOK.DESCRIPTION')"
    >
      <woot-code :script="inbox.events_webhook_url" lang="html" />
    </SettingsFieldSection>

    <div class="flex flex-col gap-3">
      <div class="flex flex-col gap-1">
        <h3 class="text-heading-3 text-n-slate-12">
          {{ $t('INBOX_MGMT.SIP_CONFIGURATION.EXTENSIONS.TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-11">
          {{ $t('INBOX_MGMT.SIP_CONFIGURATION.EXTENSIONS.DESCRIPTION') }}
        </p>
      </div>

      <p v-if="!extensions.length" class="text-sm text-n-slate-11">
        {{ $t('INBOX_MGMT.SIP_CONFIGURATION.EXTENSIONS.EMPTY') }}
      </p>

      <div
        v-for="extension in extensions"
        :key="extension.userId"
        class="grid grid-cols-1 lg:grid-cols-8 gap-3 items-center"
      >
        <div class="flex items-center gap-2 min-w-0 lg:col-span-2">
          <Avatar
            :src="extension.thumbnail"
            :name="extension.name"
            :size="24"
            rounded-full
          />
          <span class="text-sm text-n-slate-12 truncate">
            {{ extension.name }}
          </span>
        </div>
        <NextInput
          v-model="extension.sipUri"
          class="lg:col-span-3"
          :placeholder="
            $t('INBOX_MGMT.SIP_CONFIGURATION.EXTENSIONS.URI_PLACEHOLDER')
          "
        />
        <NextInput
          v-model="extension.sipPassword"
          type="password"
          class="lg:col-span-2"
          :placeholder="
            extension.hasPassword
              ? $t(
                  'INBOX_MGMT.SIP_CONFIGURATION.EXTENSIONS.SAVED_PASSWORD_PLACEHOLDER'
                )
              : $t(
                  'INBOX_MGMT.SIP_CONFIGURATION.EXTENSIONS.PASSWORD_PLACEHOLDER'
                )
          "
        />
        <NextButton
          sm
          :is-loading="savingUserId === extension.userId"
          :label="$t('INBOX_MGMT.SIP_CONFIGURATION.EXTENSIONS.SAVE')"
          @click="saveExtension(extension)"
        />
      </div>
    </div>
  </div>
</template>
