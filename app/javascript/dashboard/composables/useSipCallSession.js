import { readonly, ref, watch } from 'vue';
import SipVoiceClient from 'dashboard/api/channel/sip/sipVoiceClient';
import SipCallsAPI from 'dashboard/api/channel/sip/sipCallsAPI';
import SipExtensionsAPI from 'dashboard/api/channel/sip/sipExtensionsAPI';
import { useMapGetter } from 'dashboard/composables/store';
import { useCallsStore } from 'dashboard/stores/calls';
import {
  getVoiceCallProvider,
  VOICE_CALL_PROVIDERS,
} from 'dashboard/helper/inbox';
import {
  clearLocalCall,
  clearSipCallRinging,
  markCallDismissed,
  markLocalCall,
  markSipCallRinging,
} from 'dashboard/helper/voice';
import {
  VOICE_CALL_DIRECTION,
  VOICE_CALL_OUTBOUND_INIT_STATUS,
} from 'dashboard/components-next/message/constants';

// Module-scoped so the header button, the contact panel and the call bubble
// share one lock (mirrors useWhatsappCallSession).
const isInitiatingOutbound = ref(false);
const isInitiatingOutboundReadonly = readonly(isInitiatingOutbound);

const findCall = callSid =>
  useCallsStore().calls.find(call => call.callSid === callSid);

// The INVITE is what tells this browser its extension is being rung, so the
// call is surfaced here rather than on the account-wide message.created.
const onIncomingCall = async ({ detail }) => {
  const { callSid, isLinked, inboxId, caller } = detail;
  let call = {
    callSid,
    inboxId,
    caller,
    provider: VOICE_CALL_PROVIDERS.SIP,
    callDirection: VOICE_CALL_DIRECTION.INBOUND,
  };

  if (isLinked) {
    try {
      const data = await SipCallsAPI.lookup(callSid);
      call = {
        ...call,
        callId: data.id,
        conversationId: data.conversation_display_id,
        inboxId: data.inbox_id,
        caller: data.caller,
      };
    } catch (_) {
      // The extension is ringing either way, so the agent must still be able
      // to answer; without the lookup the call just has no thread to open.
    }
  }

  // The caller may have hung up while the call was being looked up.
  if (!SipVoiceClient.hasIncomingCall(callSid)) return;

  markSipCallRinging(callSid);
  useCallsStore().addCall(call);
};

// The contact picked up an outbound call.
const onCallAnswered = ({ detail: { callSid } }) => {
  const call = findCall(callSid);
  if (!call) return;

  useCallsStore().setCallActive(callSid);
  SipCallsAPI.accept(call.callId);
};

// The other side hung up, or the call never connected. A call that only rang
// here is still ringing elsewhere, so just this card goes away; a call this
// browser owned is closed on the backend too.
const onCallEnded = ({ detail: { callSid, wasActive } }) => {
  const call = findCall(callSid);
  clearSipCallRinging(callSid);
  clearLocalCall(callSid);
  markCallDismissed(callSid);
  if (wasActive && call?.callId) SipCallsAPI.terminate(call.callId);
  useCallsStore().dismissCall(callSid);
};

// Inboxes whose credentials were already requested; an extension added later
// is picked up on the next page load.
const requestedInboxIds = new Set();

const registerExtension = async inboxId => {
  if (requestedInboxIds.has(inboxId)) return;
  requestedInboxIds.add(inboxId);

  try {
    const {
      url,
      uri,
      password,
      ice_servers: iceServers,
    } = await SipExtensionsAPI.current(inboxId);
    if (!uri || !password) return;

    SipVoiceClient.register({ inboxId, url, uri, password, iceServers });
  } catch (_) {
    // Retried the next time the inbox list changes.
    requestedInboxIds.delete(inboxId);
  }
};

let isListening = false;

// Root-mount composable (FloatingCallWidget): registers the agent's extension
// on every SIP inbox and wires the client's events to the calls store.
export function useSipRegistration() {
  const inboxes = useMapGetter('inboxes/getInboxes');

  if (!isListening) {
    isListening = true;
    SipVoiceClient.addEventListener('call:incoming', onIncomingCall);
    SipVoiceClient.addEventListener('call:answered', onCallAnswered);
    SipVoiceClient.addEventListener('call:ended', onCallEnded);
  }

  watch(
    inboxes,
    list =>
      (list || [])
        .filter(
          inbox => getVoiceCallProvider(inbox) === VOICE_CALL_PROVIDERS.SIP
        )
        .forEach(inbox => registerExtension(inbox.id)),
    { immediate: true }
  );
}

export function useSipCallSession() {
  // target: { inboxId, conversationId } or { inboxId, contactId }
  const initiateOutboundCall = async ({
    inboxId,
    conversationId,
    contactId,
  }) => {
    if (isInitiatingOutbound.value || SipVoiceClient.hasActiveCall) {
      return { status: VOICE_CALL_OUTBOUND_INIT_STATUS.LOCKED };
    }
    if (!SipVoiceClient.hasExtension(inboxId)) {
      return { status: VOICE_CALL_OUTBOUND_INIT_STATUS.NO_EXTENSION };
    }

    isInitiatingOutbound.value = true;
    try {
      const response = await SipCallsAPI.initiate({
        conversationId,
        contactId,
        inboxId,
      });
      // Stay non-active until the contact picks up (call:answered); flipping
      // to active here would start the duration timer during ringing.
      useCallsStore().addCall({
        callSid: response.call_id,
        callId: response.id,
        conversationId: response.conversation_id,
        inboxId,
        callDirection: VOICE_CALL_DIRECTION.OUTBOUND,
        provider: VOICE_CALL_PROVIDERS.SIP,
      });
      // Before dialling, so this tab's own voice_call.accepted broadcast is
      // not mistaken for a sibling tab taking the call.
      markLocalCall(response.call_id);
      SipVoiceClient.call({
        inboxId,
        to: response.to,
        callSid: response.call_id,
      });
      return response;
    } finally {
      isInitiatingOutbound.value = false;
    }
  };

  // callId is absent for a call the PBX did not announce (see sipVoiceClient),
  // which is answered without touching the backend.
  const acceptIncomingCall = async ({ callSid, callId }) => {
    markLocalCall(callSid);
    SipVoiceClient.answer(callSid);
    clearSipCallRinging(callSid);
    if (!callId) return;

    try {
      await SipCallsAPI.accept(callId);
    } catch (error) {
      // Another agent holds the call on the backend; drop this leg.
      SipVoiceClient.hangup();
      throw error;
    }
  };

  const declineIncomingCall = callSid => {
    clearSipCallRinging(callSid);
    SipVoiceClient.decline(callSid);
  };

  const endActiveCall = async callId => {
    SipVoiceClient.hangup();
    if (callId) await SipCallsAPI.terminate(callId).catch(() => {});
  };

  return {
    isInitiating: isInitiatingOutboundReadonly,
    initiateOutboundCall,
    acceptIncomingCall,
    declineIncomingCall,
    endActiveCall,
  };
}
