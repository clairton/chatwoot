require 'rails_helper'

RSpec.describe 'SIP Extensions API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_sip, account: account) }
  let(:inbox) { channel.inbox }
  let!(:inbox_member) { create(:inbox_member, user: agent, inbox: inbox) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/sip_extensions" }

  describe 'GET /api/v1/accounts/:account_id/inboxes/:inbox_id/sip_extensions' do
    it 'lists every member extension without the password for administrators' do
      inbox_member.update!(sip_uri: 'sip:1001@pbx.example.com', sip_password: 'secret')

      get base_url, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to contain_exactly(
        a_hash_including('user_id' => agent.id, 'sip_uri' => 'sip:1001@pbx.example.com', 'has_password' => true)
      )
      expect(response.body).not_to include('secret')
    end

    it 'returns 401 for agents' do
      get base_url, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 404 for an inbox that is not a SIP inbox' do
      other_inbox = create(:inbox, account: account)

      get "/api/v1/accounts/#{account.id}/inboxes/#{other_inbox.id}/sip_extensions", headers: admin.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/inboxes/:inbox_id/sip_extensions/:id' do
    it 'sets the extension of a member' do
      patch "#{base_url}/#{agent.id}",
            params: { sip_uri: 'sip:1001@pbx.example.com', sip_password: 'secret' },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('sip_uri' => 'sip:1001@pbx.example.com', 'has_password' => true)
      expect(inbox_member.reload).to have_attributes(sip_uri: 'sip:1001@pbx.example.com', sip_password: 'secret')
    end

    it 'keeps the stored password when none is sent' do
      inbox_member.update!(sip_uri: 'sip:1001@pbx.example.com', sip_password: 'secret')

      patch "#{base_url}/#{agent.id}",
            params: { sip_uri: 'sip:1002@pbx.example.com' },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(inbox_member.reload).to have_attributes(sip_uri: 'sip:1002@pbx.example.com', sip_password: 'secret')
    end

    it 'clears the extension when the URI is blank' do
      inbox_member.update!(sip_uri: 'sip:1001@pbx.example.com', sip_password: 'secret')

      patch "#{base_url}/#{agent.id}", params: { sip_uri: '' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(inbox_member.reload).to have_attributes(sip_uri: nil, sip_password: nil)
    end

    it 'returns 422 for an invalid SIP URI' do
      patch "#{base_url}/#{agent.id}", params: { sip_uri: '1001' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns 404 for a user who is not a member of the inbox' do
      patch "#{base_url}/#{admin.id}",
            params: { sip_uri: 'sip:1001@pbx.example.com' },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 401 for agents' do
      patch "#{base_url}/#{agent.id}",
            params: { sip_uri: 'sip:1001@pbx.example.com' },
            headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/accounts/:account_id/inboxes/:inbox_id/sip_extensions/current' do
    it 'returns the signed-in agent credentials and the PBX address' do
      inbox_member.update!(sip_uri: 'sip:1001@pbx.example.com', sip_password: 'secret')

      get "#{base_url}/current", headers: agent.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        'url' => channel.url, 'uri' => 'sip:1001@pbx.example.com', 'password' => 'secret'
      )
      expect(response.parsed_body['ice_servers']).to be_present
    end

    it 'returns blank credentials when the agent has no extension' do
      get "#{base_url}/current", headers: agent.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('uri' => nil, 'password' => nil)
    end

    it 'returns 401 for an agent outside the inbox' do
      outsider = create(:user, account: account, role: :agent)

      get "#{base_url}/current", headers: outsider.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
