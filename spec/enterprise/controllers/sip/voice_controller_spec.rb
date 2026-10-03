require 'rails_helper'

RSpec.describe 'Sip::VoiceController', type: :request do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_sip, account: account) }
  let(:inbox) { channel.inbox }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:events_url) { "/sip/voice/events/#{channel.webhook_token}" }

  before do
    account.enable_features!('channel_voice')
    create(:inbox_member, user: agent, inbox: inbox, sip_uri: 'sip:1001@pbx.example.com')
  end

  describe 'POST /sip/voice/events/:token' do
    it 'creates the inbound call and returns the extensions to ring' do
      post events_url, params: { event: 'ringing', call_id: 'pbx-call-1', from: '+5511988887777' }, as: :json

      expect(response).to have_http_status(:ok)
      call = Call.sip.find_by(provider_call_id: 'pbx-call-1')
      expect(call).to have_attributes(inbox_id: inbox.id, direction: 'incoming', status: 'ringing')
      expect(response.parsed_body).to eq(
        'action' => 'ring', 'call_id' => 'pbx-call-1', 'conversation_id' => call.conversation.display_id, 'extensions' => ['1001']
      )
    end

    it 'accepts form-encoded events from a dialplan' do
      post events_url, params: { event: 'ringing', call_id: 'pbx-call-1', from: '+5511988887777' }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['action']).to eq('ring')
    end

    it 'moves an existing call along' do
      post events_url, params: { event: 'ringing', call_id: 'pbx-call-1', from: '+5511988887777' }, as: :json
      post events_url, params: { event: 'answered', call_id: 'pbx-call-1', extension: '1001' }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('call_id' => 'pbx-call-1', 'status' => 'in-progress')
      expect(Call.sip.find_by(provider_call_id: 'pbx-call-1').accepted_by_agent_id).to eq(agent.id)
    end

    it 'returns 404 for an unknown token' do
      post '/sip/voice/events/unknown-token', params: { event: 'ringing', call_id: 'pbx-call-1', from: '+5511988887777' }, as: :json

      expect(response).to have_http_status(:not_found)
      expect(Call.count).to eq(0)
    end

    it 'returns 404 when voice is not enabled for the account' do
      account.disable_features!('channel_voice')

      post events_url, params: { event: 'ringing', call_id: 'pbx-call-1', from: '+5511988887777' }, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 for an event about a call it does not know' do
      post events_url, params: { event: 'completed', call_id: 'missing' }, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 422 for an unknown event' do
      post events_url, params: { event: 'transferred', call_id: 'pbx-call-1' }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns 422 when call_id is missing' do
      post events_url, params: { event: 'completed' }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns 422 for a ringing event without the caller' do
      post events_url, params: { event: 'ringing', call_id: 'pbx-call-1' }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Call.count).to eq(0)
    end
  end
end
