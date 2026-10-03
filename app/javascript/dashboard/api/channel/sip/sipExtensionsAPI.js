/* global axios */
import ApiClient from '../../ApiClient';

class SipExtensionsAPI extends ApiClient {
  constructor() {
    super('inboxes', { accountScoped: true });
  }

  // Every member's extension, without passwords (administrators only).
  list(inboxId) {
    return axios
      .get(`${this.url}/${inboxId}/sip_extensions`)
      .then(r => r.data.payload);
  }

  save(inboxId, userId, { sipUri, sipPassword }) {
    return axios
      .patch(`${this.url}/${inboxId}/sip_extensions/${userId}`, {
        sip_uri: sipUri,
        sip_password: sipPassword,
      })
      .then(r => r.data);
  }

  // The signed-in agent's own credentials for the inbox.
  current(inboxId) {
    return axios
      .get(`${this.url}/${inboxId}/sip_extensions/current`)
      .then(r => r.data);
  }
}

export default new SipExtensionsAPI();
