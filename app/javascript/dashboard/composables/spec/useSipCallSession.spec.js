import { ref } from 'vue';
import { setActivePinia, createPinia } from 'pinia';
import SipVoiceClient from 'dashboard/api/channel/sip/sipVoiceClient';
import SipCallsAPI from 'dashboard/api/channel/sip/sipCallsAPI';
import SipExtensionsAPI from 'dashboard/api/channel/sip/sipExtensionsAPI';
import { useMapGetter } from 'dashboard/composables/store';
import { useCallsStore } from 'dashboard/stores/calls';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { handleVoiceCallCreated } from 'dashboard/helper/voice';
import { useSipCallSession, useSipRegistration } from '../useSipCallSession';

vi.mock('dashboard/api/channel/sip/sipVoiceClient', () => {
  const client = new EventTarget();
  Object.assign(client, {
    hasActiveCall: false,
    register: vi.fn(),
    hasExtension: vi.fn(),
    hasIncomingCall: vi.fn(),
    call: vi.fn(),
    answer: vi.fn(),
    decline: vi.fn(),
    hangup: vi.fn(),
  });
  return { default: client };
});
vi.mock('dashboard/api/channel/sip/sipCallsAPI', () => ({
  default: {
    lookup: vi.fn(),
    initiate: vi.fn(),
    accept: vi.fn(),
    terminate: vi.fn(),
  },
}));
vi.mock('dashboard/api/channel/sip/sipExtensionsAPI', () => ({
  default: { current: vi.fn() },
}));
vi.mock('dashboard/api/channel/voice/twilioVoiceClient', () => ({
  default: { endClientCall: vi.fn() },
}));
vi.mock('dashboard/composables/useWhatsappCallSession', () => ({
  cleanupWhatsappSession: vi.fn(),
}));
vi.mock('dashboard/composables/store');

const sipInbox = id => ({
  id,
  channel_type: INBOX_TYPES.SIP,
  voice_enabled: true,
});

const emit = (name, detail) =>
  SipVoiceClient.dispatchEvent(new CustomEvent(name, { detail }));

// Lets the async event handlers and the registration watcher settle.
const flushPromises = () =>
  new Promise(resolve => {
    setTimeout(resolve);
  });

const inboundMessage = callSid => ({
  content_type: 'voice_call',
  conversation_id: 7,
  inbox_id: 1,
  call: {
    id: 9,
    provider_call_id: callSid,
    provider: 'sip',
    status: 'ringing',
    direction: 'incoming',
  },
});

describe('useSipCallSession', () => {
  let callsStore;

  beforeEach(() => {
    setActivePinia(createPinia());
    callsStore = useCallsStore();
    SipVoiceClient.hasActiveCall = false;
    SipVoiceClient.hasExtension.mockReturnValue(true);
    SipVoiceClient.hasIncomingCall.mockReturnValue(true);
    SipCallsAPI.accept.mockResolvedValue({});
    SipCallsAPI.terminate.mockResolvedValue({});
    useMapGetter.mockReturnValue(ref([]));
    useSipRegistration();
  });

  describe('useSipRegistration', () => {
    it('registers the agent extension on every SIP voice inbox', async () => {
      SipExtensionsAPI.current.mockResolvedValue({
        url: 'wss://pbx.example.com:8089/ws',
        uri: 'sip:1001@pbx.example.com',
        password: 'secret',
        ice_servers: [{ urls: ['stun:stun.example.com'] }],
      });
      useMapGetter.mockReturnValue(
        ref([sipInbox(101), { id: 102, channel_type: INBOX_TYPES.WEB }])
      );

      useSipRegistration();
      await flushPromises();

      expect(SipExtensionsAPI.current).toHaveBeenCalledTimes(1);
      expect(SipExtensionsAPI.current).toHaveBeenCalledWith(101);
      expect(SipVoiceClient.register).toHaveBeenCalledWith({
        inboxId: 101,
        url: 'wss://pbx.example.com:8089/ws',
        uri: 'sip:1001@pbx.example.com',
        password: 'secret',
        iceServers: [{ urls: ['stun:stun.example.com'] }],
      });
    });

    it('does not register when the agent has no extension on the inbox', async () => {
      SipExtensionsAPI.current.mockResolvedValue({
        url: 'wss://pbx.example.com:8089/ws',
        uri: null,
        password: null,
      });
      useMapGetter.mockReturnValue(ref([sipInbox(103)]));

      useSipRegistration();
      await flushPromises();

      expect(SipExtensionsAPI.current).toHaveBeenCalledWith(103);
      expect(SipVoiceClient.register).not.toHaveBeenCalled();
    });

    it('asks again for an inbox whose credentials could not be fetched', async () => {
      SipExtensionsAPI.current.mockRejectedValueOnce(new Error('offline'));
      SipExtensionsAPI.current.mockResolvedValue({ uri: null });
      useMapGetter.mockReturnValue(ref([sipInbox(105)]));

      useSipRegistration();
      await flushPromises();
      useSipRegistration();
      await flushPromises();

      expect(SipExtensionsAPI.current).toHaveBeenCalledTimes(2);
    });

    it('requests the credentials of an inbox only once', async () => {
      SipExtensionsAPI.current.mockResolvedValue({ uri: null });
      useMapGetter.mockReturnValue(ref([sipInbox(104)]));

      useSipRegistration();
      useSipRegistration();
      await flushPromises();

      expect(SipExtensionsAPI.current).toHaveBeenCalledTimes(1);
    });
  });

  describe('incoming calls', () => {
    it('surfaces a call the PBX announced with its conversation and caller', async () => {
      SipCallsAPI.lookup.mockResolvedValue({
        id: 9,
        conversation_display_id: 7,
        inbox_id: 1,
        caller: { name: 'Maria', phone: '+5511988887777' },
      });

      emit('call:incoming', {
        callSid: 'pbx-call-1',
        isLinked: true,
        inboxId: 1,
        caller: { name: '', phone: '1001' },
      });
      await flushPromises();

      expect(SipCallsAPI.lookup).toHaveBeenCalledWith('pbx-call-1');
      expect(callsStore.incomingCalls).toEqual([
        {
          callSid: 'pbx-call-1',
          callId: 9,
          conversationId: 7,
          inboxId: 1,
          provider: 'sip',
          callDirection: 'inbound',
          caller: { name: 'Maria', phone: '+5511988887777' },
          isActive: false,
        },
      ]);
    });

    it('surfaces a call the PBX did not announce without looking it up', async () => {
      emit('call:incoming', {
        callSid: 'sip-call-id',
        isLinked: false,
        inboxId: 1,
        caller: { name: 'Front desk', phone: '1002' },
      });
      await flushPromises();

      expect(SipCallsAPI.lookup).not.toHaveBeenCalled();
      expect(callsStore.incomingCalls).toEqual([
        {
          callSid: 'sip-call-id',
          inboxId: 1,
          provider: 'sip',
          callDirection: 'inbound',
          caller: { name: 'Front desk', phone: '1002' },
          isActive: false,
        },
      ]);
    });

    it('still rings a call that could not be looked up', async () => {
      SipCallsAPI.lookup.mockRejectedValue(new Error('not found'));

      emit('call:incoming', {
        callSid: 'pbx-call-4',
        isLinked: true,
        inboxId: 1,
        caller: { name: '', phone: '+5511988887777' },
      });
      await flushPromises();

      expect(callsStore.incomingCalls).toEqual([
        {
          callSid: 'pbx-call-4',
          inboxId: 1,
          provider: 'sip',
          callDirection: 'inbound',
          caller: { name: '', phone: '+5511988887777' },
          isActive: false,
        },
      ]);
    });

    it('drops a call whose caller hung up while it was being looked up', async () => {
      SipCallsAPI.lookup.mockResolvedValue({ id: 9 });
      SipVoiceClient.hasIncomingCall.mockReturnValue(false);

      emit('call:incoming', { callSid: 'pbx-call-2', isLinked: true });
      await flushPromises();

      expect(callsStore.calls).toEqual([]);
    });

    it('lets the voice_call message ring only on an extension the PBX is ringing', async () => {
      handleVoiceCallCreated(inboundMessage('pbx-call-3'), 5, 'online');
      expect(callsStore.calls).toEqual([]);

      SipCallsAPI.lookup.mockResolvedValue({ id: 9, inbox_id: 1 });
      emit('call:incoming', { callSid: 'pbx-call-3', isLinked: true });
      await flushPromises();
      handleVoiceCallCreated(inboundMessage('pbx-call-3'), 5, 'online');

      expect(callsStore.calls).toHaveLength(1);
    });

    it('removes the card when the call stops ringing on this extension', async () => {
      emit('call:incoming', { callSid: 'sip-call-id-2', isLinked: false });
      await flushPromises();

      emit('call:ended', { callSid: 'sip-call-id-2', wasActive: false });

      expect(callsStore.calls).toEqual([]);
      expect(SipCallsAPI.terminate).not.toHaveBeenCalled();
    });
  });

  describe('acceptIncomingCall', () => {
    it('answers on the extension and reports the pickup', async () => {
      await useSipCallSession().acceptIncomingCall({
        callSid: 'pbx-call-1',
        callId: 9,
      });

      expect(SipVoiceClient.answer).toHaveBeenCalledWith('pbx-call-1');
      expect(SipCallsAPI.accept).toHaveBeenCalledWith(9);
    });

    it('answers a call the PBX did not announce without touching the backend', async () => {
      await useSipCallSession().acceptIncomingCall({ callSid: 'sip-call-id' });

      expect(SipVoiceClient.answer).toHaveBeenCalledWith('sip-call-id');
      expect(SipCallsAPI.accept).not.toHaveBeenCalled();
    });

    it('hangs up when the backend refuses the pickup', async () => {
      const error = new Error('conflict');
      SipCallsAPI.accept.mockRejectedValue(error);

      await expect(
        useSipCallSession().acceptIncomingCall({
          callSid: 'pbx-call-1',
          callId: 9,
        })
      ).rejects.toBe(error);

      expect(SipVoiceClient.hangup).toHaveBeenCalled();
    });
  });

  describe('initiateOutboundCall', () => {
    beforeEach(() => {
      SipCallsAPI.initiate.mockResolvedValue({
        id: 11,
        call_id: 'out-1',
        conversation_id: 7,
        to: '+5511988887777',
      });
    });

    it('records the call, then dials it from the extension of the inbox', async () => {
      const response = await useSipCallSession().initiateOutboundCall({
        inboxId: 1,
        conversationId: 7,
      });

      expect(response.id).toBe(11);
      expect(SipCallsAPI.initiate).toHaveBeenCalledWith({
        conversationId: 7,
        contactId: undefined,
        inboxId: 1,
      });
      expect(SipVoiceClient.call).toHaveBeenCalledWith({
        inboxId: 1,
        to: '+5511988887777',
        callSid: 'out-1',
      });
      expect(callsStore.incomingCalls).toEqual([
        {
          callSid: 'out-1',
          callId: 11,
          conversationId: 7,
          inboxId: 1,
          callDirection: 'outbound',
          provider: 'sip',
          isActive: false,
        },
      ]);
    });

    it('does nothing while another SIP call is live', async () => {
      SipVoiceClient.hasActiveCall = true;

      const response = await useSipCallSession().initiateOutboundCall({
        inboxId: 1,
        conversationId: 7,
      });

      expect(response).toEqual({ status: 'locked' });
      expect(SipCallsAPI.initiate).not.toHaveBeenCalled();
    });

    it('reports a missing extension instead of recording a call', async () => {
      SipVoiceClient.hasExtension.mockReturnValue(false);

      const response = await useSipCallSession().initiateOutboundCall({
        inboxId: 1,
        conversationId: 7,
      });

      expect(response).toEqual({ status: 'no_extension' });
      expect(SipCallsAPI.initiate).not.toHaveBeenCalled();
    });

    it('goes active and reports the pickup when the contact answers', async () => {
      await useSipCallSession().initiateOutboundCall({
        inboxId: 1,
        conversationId: 7,
      });

      emit('call:answered', { callSid: 'out-1' });

      expect(callsStore.activeCall.callSid).toBe('out-1');
      expect(SipCallsAPI.accept).toHaveBeenCalledWith(11);
    });

    it('closes the call on the backend when the other side hangs up', async () => {
      await useSipCallSession().initiateOutboundCall({
        inboxId: 1,
        conversationId: 7,
      });

      emit('call:ended', { callSid: 'out-1', wasActive: true });

      expect(SipCallsAPI.terminate).toHaveBeenCalledWith(11);
      expect(callsStore.calls).toEqual([]);
    });
  });

  it('declines a ringing call on this extension only', () => {
    useSipCallSession().declineIncomingCall('pbx-call-1');

    expect(SipVoiceClient.decline).toHaveBeenCalledWith('pbx-call-1');
    expect(SipCallsAPI.terminate).not.toHaveBeenCalled();
  });

  it('hangs up and closes the active call on the backend', async () => {
    await useSipCallSession().endActiveCall(9);

    expect(SipVoiceClient.hangup).toHaveBeenCalled();
    expect(SipCallsAPI.terminate).toHaveBeenCalledWith(9);
  });
});
