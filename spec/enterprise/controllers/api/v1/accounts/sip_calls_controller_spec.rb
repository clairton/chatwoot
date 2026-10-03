require 'rails_helper'

RSpec.describe 'SIP Calls API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_sip, account: account, phone_number: '+551140001000') }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:call) do
    create(:call, account: account, inbox: inbox, conversation: conversation, contact: conversation.contact,
                  provider: :sip, direction: :incoming, status: 'ringing', provider_call_id: 'pbx-call-1')
  end

  before do
    account.enable_features!('channel_voice')
    create(:inbox_member, user: agent, inbox: inbox)
  end

  describe 'GET /api/v1/accounts/:account_id/sip_calls/:id' do
    it 'returns the call payload' do
      get "/api/v1/accounts/#{account.id}/sip_calls/#{call.id}", headers: agent.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('id' => call.id, 'call_id' => 'pbx-call-1', 'provider' => 'sip')
    end

    it 'returns 401 when unauthenticated' do
      get "/api/v1/accounts/#{account.id}/sip_calls/#{call.id}"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'does not expose calls from other providers' do
      call.update!(provider: :twilio)

      get "/api/v1/accounts/#{account.id}/sip_calls/#{call.id}", headers: agent.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/v1/accounts/:account_id/sip_calls/lookup' do
    it 'resolves a call from the id the PBX put on the INVITE' do
      call

      get "/api/v1/accounts/#{account.id}/sip_calls/lookup", params: { call_id: 'pbx-call-1' },
                                                             headers: agent.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        'id' => call.id, 'inbox_id' => inbox.id, 'direction' => 'inbound', 'conversation_display_id' => conversation.display_id
      )
    end

    it 'returns 404 for an unknown call id' do
      get "/api/v1/accounts/#{account.id}/sip_calls/lookup", params: { call_id: 'missing' },
                                                             headers: agent.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 401 for an agent who cannot see the conversation' do
      call
      outsider = create(:user, account: account, role: :agent)

      get "/api/v1/accounts/#{account.id}/sip_calls/lookup", params: { call_id: 'pbx-call-1' },
                                                             headers: outsider.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/sip_calls/:id/accept' do
    it 'accepts the call without an SDP answer' do
      post "/api/v1/accounts/#{account.id}/sip_calls/#{call.id}/accept", headers: agent.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(call.reload).to have_attributes(status: 'in_progress', accepted_by_agent_id: agent.id)
      expect(conversation.reload.assignee_id).to eq(agent.id)
    end

    it 'returns 409 when another agent already accepted the call' do
      other_agent = create(:user, account: account, role: :agent)
      call.update!(status: 'in_progress', accepted_by_agent_id: other_agent.id)

      post "/api/v1/accounts/#{account.id}/sip_calls/#{call.id}/accept", headers: agent.create_new_auth_token

      expect(response).to have_http_status(:conflict)
    end

    it 'returns 409 when the call has already ended' do
      call.update!(status: 'no_answer')

      post "/api/v1/accounts/#{account.id}/sip_calls/#{call.id}/accept", headers: agent.create_new_auth_token

      expect(response).to have_http_status(:conflict)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/sip_calls/:id/terminate' do
    it 'ends the call and returns its new status' do
      call.update!(status: 'in_progress', accepted_by_agent_id: agent.id, started_at: 10.seconds.ago)

      post "/api/v1/accounts/#{account.id}/sip_calls/#{call.id}/terminate", headers: agent.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['status']).to eq('completed')
      expect(call.reload.status).to eq('completed')
    end
  end

  describe 'POST /api/v1/accounts/:account_id/sip_calls/initiate' do
    let(:contact) { create(:contact, account: account, phone_number: '+5511988887777') }

    it 'records an outbound call in the conversation and returns the id and number to dial' do
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: contact.phone_number)
      initiate_conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)

      post "/api/v1/accounts/#{account.id}/sip_calls/initiate",
           params: { conversation_id: initiate_conversation.display_id }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:ok)
      created_call = account.calls.sip.last
      expect(response.parsed_body).to include(
        'status' => 'calling', 'provider' => 'sip', 'id' => created_call.id,
        'call_id' => created_call.provider_call_id, 'to' => '+5511988887777',
        'conversation_id' => initiate_conversation.display_id
      )
      expect(created_call).to have_attributes(
        direction: 'outgoing', status: 'ringing', accepted_by_agent_id: agent.id, conversation_id: initiate_conversation.id
      )
      expect(created_call.message).to have_attributes(content_type: 'voice_call', message_type: 'outgoing')
      expect(initiate_conversation.reload.assignee_id).to eq(agent.id)
    end

    it 'opens a conversation keyed by the phone number when calling from the contact' do
      post "/api/v1/accounts/#{account.id}/sip_calls/initiate",
           params: { contact_id: contact.id, inbox_id: inbox.id }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:ok)
      created_call = account.calls.sip.last
      expect(created_call.conversation).to have_attributes(inbox_id: inbox.id, contact_id: contact.id, assignee_id: agent.id)
      expect(created_call.conversation.contact_inbox.source_id).to eq('+5511988887777')
    end

    it 'returns 422 when the contact has no phone number' do
      contact.update!(phone_number: nil, email: 'caller@example.com')

      post "/api/v1/accounts/#{account.id}/sip_calls/initiate",
           params: { contact_id: contact.id, inbox_id: inbox.id }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.calls.count).to eq(0)
    end

    it 'returns 422 when the inbox is not a SIP inbox' do
      other_inbox = create(:inbox, account: account)
      create(:inbox_member, user: agent, inbox: other_inbox)

      post "/api/v1/accounts/#{account.id}/sip_calls/initiate",
           params: { contact_id: contact.id, inbox_id: other_inbox.id }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns 422 when voice is not enabled for the account' do
      account.disable_features!('channel_voice')

      post "/api/v1/accounts/#{account.id}/sip_calls/initiate",
           params: { contact_id: contact.id, inbox_id: inbox.id }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
