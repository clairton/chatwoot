/* global axios */
import ApiClient from '../../ApiClient';

class SipCallsAPI extends ApiClient {
  constructor() {
    super('sip_calls', { accountScoped: true });
  }

  // Resolves a call from the id the PBX put on the INVITE.
  lookup(callSid) {
    return axios
      .get(`${this.url}/lookup`, { params: { call_id: callSid } })
      .then(r => r.data);
  }

  // Either conversationId, or contactId + inboxId to let the BE resolve the conversation.
  initiate({ conversationId, contactId, inboxId }) {
    return axios
      .post(`${this.url}/initiate`, {
        conversation_id: conversationId,
        contact_id: contactId,
        inbox_id: inboxId,
      })
      .then(r => r.data);
  }

  accept(callId) {
    return axios.post(`${this.url}/${callId}/accept`).then(r => r.data);
  }

  terminate(callId) {
    return axios.post(`${this.url}/${callId}/terminate`).then(r => r.data);
  }
}

export default new SipCallsAPI();
