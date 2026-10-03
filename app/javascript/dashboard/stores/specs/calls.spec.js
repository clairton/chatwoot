import { setActivePinia, createPinia } from 'pinia';
import SipVoiceClient from 'dashboard/api/channel/sip/sipVoiceClient';
import TwilioVoiceClient from 'dashboard/api/channel/voice/twilioVoiceClient';
import { useCallsStore } from '../calls';

vi.mock('dashboard/api/channel/sip/sipVoiceClient', () => ({
  default: { hangup: vi.fn() },
}));
vi.mock('dashboard/api/channel/voice/twilioVoiceClient', () => ({
  default: { endClientCall: vi.fn() },
}));
vi.mock('dashboard/composables/useWhatsappCallSession', () => ({
  cleanupWhatsappSession: vi.fn(),
}));

describe('calls store', () => {
  let store;

  beforeEach(() => {
    setActivePinia(createPinia());
    store = useCallsStore();
  });

  it('hangs up the SIP session when an active SIP call is removed', () => {
    store.addCall({ callSid: 'pbx-call-1', provider: 'sip' });
    store.setCallActive('pbx-call-1');

    store.removeCall('pbx-call-1');

    expect(SipVoiceClient.hangup).toHaveBeenCalled();
    expect(TwilioVoiceClient.endClientCall).not.toHaveBeenCalled();
    expect(store.calls).toEqual([]);
  });

  it('leaves the SIP session alone when a ringing SIP call is removed', () => {
    store.addCall({ callSid: 'pbx-call-1', provider: 'sip' });

    store.removeCall('pbx-call-1');

    expect(SipVoiceClient.hangup).not.toHaveBeenCalled();
    expect(store.calls).toEqual([]);
  });
});
