import JsSIP from 'jssip';
import SipVoiceClient, {
  CALL_ID_HEADER,
} from '../../../channel/sip/sipVoiceClient';

vi.mock('jssip', () => ({
  default: { UA: vi.fn(), WebSocketInterface: vi.fn() },
}));

// Minimal stand-ins for JsSIP's emitters: `on` registers, `emit` fires.
const createEmitter = () => {
  const handlers = {};
  return {
    on: vi.fn((event, handler) => {
      handlers[event] = handler;
    }),
    emit: (event, payload) => handlers[event]?.(payload),
  };
};

const createSession = () => ({
  ...createEmitter(),
  connection: null,
  remote_identity: { display_name: 'Maria', uri: { user: '+5511988887777' } },
  answer: vi.fn(),
  terminate: vi.fn(),
  mute: vi.fn(),
  unmute: vi.fn(),
  isEnded: vi.fn(() => false),
});

const createRequest = callSid => ({
  call_id: 'sip-call-id',
  getHeader: name => (name === CALL_ID_HEADER ? callSid : undefined),
});

const EXTENSION = {
  inboxId: 1,
  url: 'wss://pbx.example.com:8089/ws',
  uri: 'sip:1001@pbx.example.com',
  password: 'secret',
  iceServers: [{ urls: ['stun:stun.example.com'] }],
};

describe('SipVoiceClient', () => {
  let userAgent;
  let events;
  let listeners;

  // The client is a singleton, so listeners are removed again after each test.
  const listen = name => {
    const listener = ({ detail }) => events.push({ name, ...detail });
    listeners.push([name, listener]);
    SipVoiceClient.addEventListener(name, listener);
  };

  const ring = (session, callSid) =>
    userAgent.emit('newRTCSession', {
      originator: 'remote',
      session,
      request: createRequest(callSid),
    });

  beforeEach(() => {
    SipVoiceClient.agents.clear();
    SipVoiceClient.incomingCalls.clear();
    SipVoiceClient.activeSession = null;
    events = [];
    listeners = [];
    userAgent = { ...createEmitter(), start: vi.fn(), call: vi.fn() };
    JsSIP.UA.mockImplementation(() => userAgent);
    SipVoiceClient.register(EXTENSION);
  });

  afterEach(() => {
    listeners.forEach(([name, listener]) =>
      SipVoiceClient.removeEventListener(name, listener)
    );
  });

  describe('#register', () => {
    it('registers the extension with the PBX', () => {
      expect(JsSIP.WebSocketInterface).toHaveBeenCalledWith(EXTENSION.url);
      expect(JsSIP.UA).toHaveBeenCalledWith(
        expect.objectContaining({
          uri: EXTENSION.uri,
          password: EXTENSION.password,
          register: true,
        })
      );
      expect(userAgent.start).toHaveBeenCalled();
      expect(SipVoiceClient.hasExtension(1)).toBe(true);
      expect(SipVoiceClient.hasExtension(2)).toBe(false);
    });

    it('shares one registration between inboxes that use the same extension', () => {
      SipVoiceClient.register({ ...EXTENSION, inboxId: 2 });

      expect(JsSIP.UA).toHaveBeenCalledTimes(1);
      expect(SipVoiceClient.hasExtension(2)).toBe(true);
    });
  });

  describe('incoming calls', () => {
    it('announces a call keyed by the id the PBX put on the INVITE', () => {
      listen('call:incoming');

      ring(createSession(), 'pbx-call-1');

      expect(events).toEqual([
        {
          name: 'call:incoming',
          callSid: 'pbx-call-1',
          isLinked: true,
          inboxId: 1,
          caller: { name: 'Maria', phone: '+5511988887777' },
        },
      ]);
      expect(SipVoiceClient.hasIncomingCall('pbx-call-1')).toBe(true);
    });

    it('falls back to the SIP Call-ID for a call the PBX did not announce', () => {
      listen('call:incoming');

      ring(createSession(), undefined);

      expect(events[0]).toMatchObject({
        callSid: 'sip-call-id',
        isLinked: false,
      });
    });

    it('answers busy when another call is already live', () => {
      ring(createSession(), 'pbx-call-1');
      SipVoiceClient.answer('pbx-call-1');
      const secondSession = createSession();

      ring(secondSession, 'pbx-call-2');

      expect(secondSession.terminate).toHaveBeenCalledWith({
        status_code: 486,
      });
      expect(SipVoiceClient.hasIncomingCall('pbx-call-2')).toBe(false);
    });

    it('answers the ringing session and makes it the active call', () => {
      const session = createSession();
      ring(session, 'pbx-call-1');

      SipVoiceClient.answer('pbx-call-1');

      expect(session.answer).toHaveBeenCalledWith({
        mediaConstraints: { audio: true, video: false },
        pcConfig: { iceServers: EXTENSION.iceServers },
      });
      expect(SipVoiceClient.hasActiveCall).toBe(true);
      expect(SipVoiceClient.hasIncomingCall('pbx-call-1')).toBe(false);
    });

    it('throws when asked to answer a call that is not ringing here', () => {
      expect(() => SipVoiceClient.answer('missing')).toThrow();
    });

    it('declines only this extension without announcing an end', () => {
      listen('call:ended');
      const session = createSession();
      ring(session, 'pbx-call-1');

      SipVoiceClient.decline('pbx-call-1');
      session.emit('failed', { originator: 'local' });

      expect(session.terminate).toHaveBeenCalledWith({ status_code: 486 });
      expect(events).toEqual([]);
    });

    it('announces the end when the caller gives up before pickup', () => {
      listen('call:ended');
      const session = createSession();
      ring(session, 'pbx-call-1');

      session.emit('failed', { originator: 'remote' });

      expect(events).toEqual([
        { name: 'call:ended', callSid: 'pbx-call-1', wasActive: false },
      ]);
      expect(SipVoiceClient.hasIncomingCall('pbx-call-1')).toBe(false);
    });
  });

  describe('outbound calls', () => {
    let session;

    beforeEach(() => {
      session = createSession();
      userAgent.call.mockReturnValue(session);
      SipVoiceClient.call({
        inboxId: 1,
        to: '+5511988887777',
        callSid: 'out-1',
      });
    });

    it('dials through the extension of the inbox with the call id header', () => {
      expect(userAgent.call).toHaveBeenCalledWith('+5511988887777', {
        mediaConstraints: { audio: true, video: false },
        pcConfig: { iceServers: EXTENSION.iceServers },
        extraHeaders: [`${CALL_ID_HEADER}: out-1`],
      });
      expect(SipVoiceClient.hasActiveCall).toBe(true);
    });

    it('announces the pickup', () => {
      listen('call:answered');

      session.emit('confirmed', {});

      expect(events).toEqual([{ name: 'call:answered', callSid: 'out-1' }]);
    });

    it('announces the end when the other side hangs up', () => {
      listen('call:ended');

      session.emit('ended', { originator: 'remote' });

      expect(events).toEqual([
        { name: 'call:ended', callSid: 'out-1', wasActive: true },
      ]);
      expect(SipVoiceClient.hasActiveCall).toBe(false);
    });

    it('hangs up without announcing an end it started itself', () => {
      listen('call:ended');

      SipVoiceClient.hangup();
      session.emit('ended', { originator: 'local' });

      expect(session.terminate).toHaveBeenCalled();
      expect(SipVoiceClient.hasActiveCall).toBe(false);
      expect(events).toEqual([]);
    });

    it('does not terminate a session that has already ended', () => {
      session.isEnded.mockReturnValue(true);

      SipVoiceClient.hangup();

      expect(session.terminate).not.toHaveBeenCalled();
    });

    it('mutes and unmutes the active call', () => {
      expect(SipVoiceClient.setMuted(true)).toBe(true);
      expect(session.mute).toHaveBeenCalledWith({ audio: true });

      expect(SipVoiceClient.setMuted(false)).toBe(false);
      expect(session.unmute).toHaveBeenCalledWith({ audio: true });
    });
  });

  it('plays the remote audio once the peer connection delivers a track', () => {
    const session = createSession();
    const peerconnection = new EventTarget();
    const stream = {};
    ring(session, 'pbx-call-1');

    session.emit('peerconnection', { peerconnection });
    const trackEvent = new Event('track');
    trackEvent.streams = [stream];
    peerconnection.dispatchEvent(trackEvent);

    expect(SipVoiceClient.remoteAudio.srcObject).toBe(stream);
  });
});
