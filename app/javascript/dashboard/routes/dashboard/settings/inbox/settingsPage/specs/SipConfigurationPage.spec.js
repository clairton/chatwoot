import { flushPromises, mount } from '@vue/test-utils';
import SipExtensionsAPI from 'dashboard/api/channel/sip/sipExtensionsAPI';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import SipConfigurationPage from '../SipConfigurationPage.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store');
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/inboxes', () => ({
  default: { setInboundCalls: vi.fn() },
}));
vi.mock('dashboard/api/channel/sip/sipExtensionsAPI', () => ({
  default: { list: vi.fn(), save: vi.fn() },
}));

const INBOX = {
  id: 1,
  url: 'wss://pbx.example.com:8089/ws',
  phone_number: '+551140001000',
  inbound_calls_enabled: true,
  events_webhook_url: 'https://app.example.com/sip/voice/events/token',
};

const NextInput = {
  props: ['modelValue', 'placeholder'],
  emits: ['update:modelValue'],
  template:
    '<input :value="modelValue" :placeholder="placeholder" @input="$emit(\'update:modelValue\', $event.target.value)" />',
};

const mountComponent = () =>
  mount(SipConfigurationPage, {
    props: { inbox: INBOX },
    global: {
      mocks: { $t: key => key },
      stubs: {
        SettingsFieldSection: { template: '<section><slot /></section>' },
        SettingsToggleSection: true,
        Avatar: true,
        NextInput,
        NextButton: {
          props: ['label'],
          template: '<button>{{ label }}</button>',
        },
        'woot-code': true,
      },
    },
  });

describe('SipConfigurationPage', () => {
  let dispatch;

  beforeEach(() => {
    dispatch = vi.fn().mockResolvedValue();
    useStore.mockReturnValue({ dispatch });
    SipExtensionsAPI.list.mockResolvedValue([
      {
        user_id: 5,
        name: 'Ana',
        thumbnail: '',
        sip_uri: 'sip:1001@pbx.example.com',
        has_password: true,
      },
      { user_id: 6, name: 'Bruno', thumbnail: '', sip_uri: null },
    ]);
  });

  const extensionRow = (wrapper, name) =>
    wrapper.findAll('.grid').find(row => row.text().includes(name));

  it('lists the extension of every inbox member', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    expect(SipExtensionsAPI.list).toHaveBeenCalledWith(1);
    const [uri, password] = extensionRow(wrapper, 'Ana').findAll('input');
    expect(uri.element.value).toBe('sip:1001@pbx.example.com');
    // The saved password never comes back; the placeholder says it is there.
    expect(password.element.value).toBe('');
    expect(password.attributes('placeholder')).toBe(
      'INBOX_MGMT.SIP_CONFIGURATION.EXTENSIONS.SAVED_PASSWORD_PLACEHOLDER'
    );
  });

  it('saves the extension of a member', async () => {
    SipExtensionsAPI.save.mockResolvedValue({ has_password: true });
    const wrapper = mountComponent();
    await flushPromises();
    const row = extensionRow(wrapper, 'Bruno');
    const [uri, password] = row.findAll('input');

    await uri.setValue('sip:1002@pbx.example.com');
    await password.setValue('secret');
    await row.find('button').trigger('click');
    await flushPromises();

    expect(SipExtensionsAPI.save).toHaveBeenCalledWith(1, 6, {
      sipUri: 'sip:1002@pbx.example.com',
      sipPassword: 'secret',
    });
    expect(row.findAll('input')[1].element.value).toBe('');
    expect(useAlert).toHaveBeenCalledWith(
      'INBOX_MGMT.SIP_CONFIGURATION.EXTENSIONS.SUCCESS_MESSAGE'
    );
  });

  it('reports an extension the backend rejected', async () => {
    SipExtensionsAPI.save.mockRejectedValue(new Error('invalid'));
    const wrapper = mountComponent();
    await flushPromises();

    await extensionRow(wrapper, 'Ana').find('button').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'INBOX_MGMT.SIP_CONFIGURATION.EXTENSIONS.ERROR_MESSAGE'
    );
  });

  it('updates the PBX address and number of the inbox', async () => {
    const wrapper = mountComponent();
    await flushPromises();
    const [url] = wrapper.findAll('input');

    await url.setValue('wss://new-pbx.example.com/ws');
    await wrapper.find('button').trigger('click');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('inboxes/updateInbox', {
      id: 1,
      formData: false,
      channel: {
        url: 'wss://new-pbx.example.com/ws',
        phone_number: '+551140001000',
      },
    });
  });
});
