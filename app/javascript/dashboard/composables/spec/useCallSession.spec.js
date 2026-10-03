import { setActivePinia, createPinia } from 'pinia';
import { useCallsStore } from 'dashboard/stores/calls';
import { useSipCallSession } from 'dashboard/composables/useSipCallSession';
import { isLocalCall } from 'dashboard/helper/voice';
import { useCallActions } from '../useCallSession';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vuex', () => ({ useStore: vi.fn() }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/channel/voice/voiceAPIClient', () => ({
  default: { joinConference: vi.fn(), leaveConference: vi.fn() },
}));
vi.mock('dashboard/api/channel/voice/twilioVoiceClient', () => ({
  default: {
    initializeDevice: vi.fn(),
    joinClientCall: vi.fn(),
    endClientCall: vi.fn(),
  },
}));
vi.mock('dashboard/api/channel/sip/sipVoiceClient', () => ({
  default: { hangup: vi.fn() },
}));
vi.mock('dashboard/composables/useWhatsappCallSession', () => ({
  useWhatsappCallSession: vi.fn(() => ({})),
  sendWhatsappTerminateBeacon: vi.fn(),
  cleanupWhatsappSession: vi.fn(),
}));
vi.mock('dashboard/composables/useSipCallSession', () => ({
  useSipCallSession: vi.fn(),
}));

describe('useCallActions with SIP calls', () => {
  let callsStore;
  let sipSession;

  beforeEach(() => {
    setActivePinia(createPinia());
    callsStore = useCallsStore();
    sipSession = {
      acceptIncomingCall: vi.fn().mockResolvedValue(),
      declineIncomingCall: vi.fn(),
      endActiveCall: vi.fn().mockResolvedValue(),
    };
    useSipCallSession.mockReturnValue(sipSession);
  });

  const addSipCall = callDirection =>
    callsStore.addCall({
      callSid: 'pbx-call-1',
      callId: 9,
      provider: 'sip',
      conversationId: 7,
      inboxId: 1,
      callDirection,
    });

  it('answers an inbound call on the extension and makes it active', async () => {
    addSipCall('inbound');

    const result = await useCallActions().joinCall({
      conversationId: 7,
      inboxId: 1,
      callSid: 'pbx-call-1',
    });

    expect(sipSession.acceptIncomingCall).toHaveBeenCalledWith({
      callSid: 'pbx-call-1',
      callId: 9,
    });
    expect(result).toEqual({ callId: 9 });
    expect(callsStore.activeCall.callSid).toBe('pbx-call-1');
  });

  it('keeps the call ringing and releases it when answering fails', async () => {
    addSipCall('inbound');
    sipSession.acceptIncomingCall.mockRejectedValue(new Error('no session'));

    const result = await useCallActions().joinCall({
      conversationId: 7,
      inboxId: 1,
      callSid: 'pbx-call-1',
    });

    expect(result).toBeNull();
    expect(callsStore.hasActiveCall).toBe(false);
    expect(isLocalCall('pbx-call-1')).toBe(false);
  });

  it('has no join step for an outbound call the browser is already dialling', async () => {
    addSipCall('outbound');

    const result = await useCallActions().joinCall({
      conversationId: 7,
      inboxId: 1,
      callSid: 'pbx-call-1',
    });

    expect(result).toBeNull();
    expect(sipSession.acceptIncomingCall).not.toHaveBeenCalled();
  });

  it('ends the active call through the SIP session', async () => {
    addSipCall('inbound');
    callsStore.setCallActive('pbx-call-1');

    await useCallActions().endCall({
      conversationId: 7,
      inboxId: 1,
      callSid: 'pbx-call-1',
    });

    expect(sipSession.endActiveCall).toHaveBeenCalledWith(9);
    expect(callsStore.calls).toEqual([]);
  });

  it('declines a ringing inbound call on this extension only', async () => {
    addSipCall('inbound');

    await useCallActions().rejectIncomingCall('pbx-call-1');

    expect(sipSession.declineIncomingCall).toHaveBeenCalledWith('pbx-call-1');
    expect(sipSession.endActiveCall).not.toHaveBeenCalled();
    expect(callsStore.calls).toEqual([]);
  });

  it('cancels a ringing outbound call on the backend too', async () => {
    addSipCall('outbound');

    await useCallActions().rejectIncomingCall('pbx-call-1');

    expect(sipSession.endActiveCall).toHaveBeenCalledWith(9);
    expect(callsStore.calls).toEqual([]);
  });
});
