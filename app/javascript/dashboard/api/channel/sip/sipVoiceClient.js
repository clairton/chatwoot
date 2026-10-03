import JsSIP from 'jssip';

// The PBX (inbound) or the browser (outbound) puts the Chatwoot call id on the
// INVITE, so both sides refer to the call by the same id.
export const CALL_ID_HEADER = 'X-Chatwoot-Call-Id';

const SIP_BUSY_HERE = 486;
const MEDIA_CONSTRAINTS = { audio: true, video: false };

const createEvent = (name, detail) => new CustomEvent(name, { detail });

// Thin wrapper over JsSIP: registers the agent's extension(s) with the PBX and
// carries the media. It knows nothing about Chatwoot calls; listeners turn its
// events into store and API updates.
//
// Events: `call:incoming` { callSid, isLinked, inboxId, caller }, `call:answered`
// { callSid } (outbound pickup) and `call:ended` { callSid, wasActive } (ended by
// the other side, or before it connected).
class SipVoiceClient extends EventTarget {
  constructor() {
    super();
    // One user agent per extension (PBX address + SIP URI); inboxes that share
    // an extension share its registration.
    this.agents = new Map();
    this.incomingCalls = new Map();
    this.activeSession = null;
    this.remoteAudio = null;
  }

  get hasActiveCall() {
    return !!this.activeSession;
  }

  register({ inboxId, url, uri, password, iceServers }) {
    const key = `${url}|${uri}`;
    const existing = this.agents.get(key);
    if (existing) {
      existing.inboxIds.add(inboxId);
      return;
    }

    const agent = { iceServers, inboxIds: new Set([inboxId]) };
    agent.ua = new JsSIP.UA({
      sockets: [new JsSIP.WebSocketInterface(url)],
      uri,
      password,
      register: true,
      session_timers: false,
    });
    agent.ua.on('newRTCSession', ({ originator, session, request }) => {
      if (originator === 'remote') {
        this.onIncomingSession(agent, session, request);
      }
    });
    agent.ua.start();
    this.agents.set(key, agent);
  }

  hasExtension(inboxId) {
    return !!this.agentFor(inboxId);
  }

  hasIncomingCall(callSid) {
    return this.incomingCalls.has(callSid);
  }

  call({ inboxId, to, callSid }) {
    const agent = this.agentFor(inboxId);
    const session = agent.ua.call(to, {
      mediaConstraints: MEDIA_CONSTRAINTS,
      pcConfig: { iceServers: agent.iceServers },
      extraHeaders: [`${CALL_ID_HEADER}: ${callSid}`],
    });
    this.activeSession = session;
    this.playRemoteAudio(session);
    session.on('confirmed', () =>
      this.dispatchEvent(createEvent('call:answered', { callSid }))
    );
    this.watchSessionEnd(callSid, session);
  }

  answer(callSid) {
    const incoming = this.incomingCalls.get(callSid);
    if (!incoming) throw new Error(`No incoming SIP call for ${callSid}`);

    this.incomingCalls.delete(callSid);
    this.activeSession = incoming.session;
    incoming.session.answer({
      mediaConstraints: MEDIA_CONSTRAINTS,
      pcConfig: { iceServers: incoming.iceServers },
    });
  }

  // Only this extension stops ringing; the PBX keeps ringing the others.
  decline(callSid) {
    const incoming = this.incomingCalls.get(callSid);
    if (!incoming) return;

    this.incomingCalls.delete(callSid);
    incoming.session.terminate({ status_code: SIP_BUSY_HERE });
  }

  hangup() {
    const session = this.activeSession;
    if (!session) return;

    this.clearActiveSession();
    if (!session.isEnded()) session.terminate();
  }

  setMuted(shouldMute) {
    if (!this.activeSession) return false;

    if (shouldMute) {
      this.activeSession.mute({ audio: true });
    } else {
      this.activeSession.unmute({ audio: true });
    }
    return shouldMute;
  }

  agentFor(inboxId) {
    return [...this.agents.values()].find(agent => agent.inboxIds.has(inboxId));
  }

  onIncomingSession(agent, session, request) {
    // No call waiting: a second call while one is live is answered busy.
    if (this.activeSession) {
      session.terminate({ status_code: SIP_BUSY_HERE });
      return;
    }

    // An INVITE without the header was not announced to Chatwoot (an internal
    // extension-to-extension call, for instance); it still rings, keyed by its
    // own SIP Call-ID.
    const linkedCallSid = request.getHeader(CALL_ID_HEADER);
    const callSid = linkedCallSid || request.call_id;
    this.incomingCalls.set(callSid, { session, iceServers: agent.iceServers });
    this.playRemoteAudio(session);
    this.watchSessionEnd(callSid, session);

    const { display_name: name, uri } = session.remote_identity;
    this.dispatchEvent(
      createEvent('call:incoming', {
        callSid,
        isLinked: !!linkedCallSid,
        inboxId: [...agent.inboxIds][0],
        caller: { name: name || '', phone: uri.user },
      })
    );
  }

  watchSessionEnd(callSid, session) {
    const onEnd = () => this.onSessionEnd(callSid, session);
    session.on('ended', onEnd);
    session.on('failed', onEnd);
  }

  // Sessions closed from this side (decline, hangup) are untracked before they
  // terminate, so only an end we did not start gets announced.
  onSessionEnd(callSid, session) {
    const wasActive = this.activeSession === session;
    const wasRinging = this.incomingCalls.get(callSid)?.session === session;
    if (!wasActive && !wasRinging) return;

    if (wasActive) this.clearActiveSession();
    this.incomingCalls.delete(callSid);
    this.dispatchEvent(createEvent('call:ended', { callSid, wasActive }));
  }

  clearActiveSession() {
    this.activeSession = null;
    if (this.remoteAudio) this.remoteAudio.srcObject = null;
  }

  // The peer connection exists up front on outbound sessions and only after
  // answer() on inbound ones.
  playRemoteAudio(session) {
    const attach = peerconnection =>
      peerconnection.addEventListener('track', ({ streams }) => {
        this.audioElement().srcObject = streams[0];
      });

    if (session.connection) {
      attach(session.connection);
    } else {
      session.on('peerconnection', ({ peerconnection }) =>
        attach(peerconnection)
      );
    }
  }

  audioElement() {
    if (!this.remoteAudio) {
      this.remoteAudio = document.createElement('audio');
      this.remoteAudio.autoplay = true;
      document.body.appendChild(this.remoteAudio);
    }
    return this.remoteAudio;
  }
}

export default new SipVoiceClient();
