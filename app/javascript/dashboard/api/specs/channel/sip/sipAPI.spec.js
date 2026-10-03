import sipCallsAPI from '../../../channel/sip/sipCallsAPI';
import sipExtensionsAPI from '../../../channel/sip/sipExtensionsAPI';

describe('SIP APIs', () => {
  const originalAxios = window.axios;
  const axiosMock = { get: vi.fn(), post: vi.fn(), patch: vi.fn() };

  beforeEach(() => {
    window.axios = axiosMock;
    axiosMock.get.mockResolvedValue({ data: { payload: [] } });
    axiosMock.post.mockResolvedValue({ data: {} });
    axiosMock.patch.mockResolvedValue({ data: {} });
  });

  afterEach(() => {
    window.axios = originalAxios;
  });

  describe('#sipCallsAPI', () => {
    it('#lookup', () => {
      sipCallsAPI.lookup('pbx-call-1');
      expect(axiosMock.get).toHaveBeenCalledWith('/api/v1/sip_calls/lookup', {
        params: { call_id: 'pbx-call-1' },
      });
    });

    it('#initiate', () => {
      sipCallsAPI.initiate({ conversationId: 7, inboxId: 1 });
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/sip_calls/initiate',
        {
          conversation_id: 7,
          contact_id: undefined,
          inbox_id: 1,
        }
      );
    });

    it('#accept', () => {
      sipCallsAPI.accept(9);
      expect(axiosMock.post).toHaveBeenCalledWith('/api/v1/sip_calls/9/accept');
    });

    it('#terminate', () => {
      sipCallsAPI.terminate(9);
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/sip_calls/9/terminate'
      );
    });
  });

  describe('#sipExtensionsAPI', () => {
    it('#list', async () => {
      await expect(sipExtensionsAPI.list(1)).resolves.toEqual([]);
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/inboxes/1/sip_extensions'
      );
    });

    it('#save', () => {
      sipExtensionsAPI.save(1, 5, {
        sipUri: 'sip:1001@pbx.example.com',
        sipPassword: 'secret',
      });
      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/inboxes/1/sip_extensions/5',
        { sip_uri: 'sip:1001@pbx.example.com', sip_password: 'secret' }
      );
    });

    it('#current', () => {
      sipExtensionsAPI.current(1);
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/inboxes/1/sip_extensions/current'
      );
    });
  });
});
