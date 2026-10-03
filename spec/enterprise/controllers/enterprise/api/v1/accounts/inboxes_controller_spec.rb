require 'rails_helper'

RSpec.describe 'Enterprise Inboxes API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  describe 'POST /api/v1/accounts/{account.id}/inboxes' do
    let(:inbox) { create(:inbox, account: account) }

    context 'when it is an authenticated user' do
      let(:admin) { create(:user, account: account, role: :administrator) }
      let(:valid_params) do
        { name: 'test', auto_assignment_config: { max_assignment_limit: 10 }, channel: { type: 'web_widget', website_url: 'test.com' } }
      end

      it 'creates a webwidget inbox with auto assignment config' do
        post "/api/v1/accounts/#{account.id}/inboxes",
             headers: admin.create_new_auth_token,
             params: valid_params,
             as: :json

        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)['auto_assignment_config']['max_assignment_limit']).to eq 10
      end

      it 'creates a voice inbox when administrator' do
        account.enable_features('channel_voice')
        account.save!
        stub_request(:get, %r{api\.twilio\.com/2010-04-01/Accounts/.*/IncomingPhoneNumbers\.json})
          .to_return(status: 200, body: { incoming_phone_numbers: [{ capabilities: { 'voice' => true } }] }.to_json,
                     headers: { 'Content-Type' => 'application/json' })
        allow(Twilio::VoiceWebhookSetupService).to receive(:new).and_return(instance_double(Twilio::VoiceWebhookSetupService,
                                                                                            perform: "AP#{SecureRandom.hex(16)}"))
        post "/api/v1/accounts/#{account.id}/inboxes",
             headers: admin.create_new_auth_token,
             params: { name: 'Voice Inbox',
                       channel: { type: 'voice', phone_number: '+15551234567',
                                  provider_config: { account_sid: "AC#{SecureRandom.hex(16)}",
                                                     auth_token: SecureRandom.hex(16),
                                                     api_key_sid: SecureRandom.hex(8),
                                                     api_key_secret: SecureRandom.hex(16) } } },
             as: :json

        expect(response).to have_http_status(:success)
        expect(response.body).to include('Voice Inbox')
        expect(response.body).to include('+15551234567')
        # the number must also receive SMS, not just calls
        expect(Channels::Twilio::WebhookSetupJob).to have_been_enqueued
      end

      it 'creates a SIP voice inbox when the provider is sip' do
        account.enable_features!('channel_voice')

        post "/api/v1/accounts/#{account.id}/inboxes",
             headers: admin.create_new_auth_token,
             params: { name: 'PBX', channel: { type: 'voice', provider: 'sip', url: 'wss://pbx.example.com:8089/ws',
                                               phone_number: '+5511999990000' } },
             as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body).to include(
          'name' => 'PBX', 'channel_type' => 'Channel::Sip', 'url' => 'wss://pbx.example.com:8089/ws',
          'phone_number' => '+5511999990000', 'voice_enabled' => true, 'inbound_calls_enabled' => true,
          'recording_enabled' => false
        )
        expect(account.sip_channels.count).to eq(1)
      end

      it 'rejects a SIP voice inbox without a websocket url' do
        account.enable_features!('channel_voice')

        post "/api/v1/accounts/#{account.id}/inboxes",
             headers: admin.create_new_auth_token,
             params: { name: 'PBX', channel: { type: 'voice', provider: 'sip', url: 'https://pbx.example.com' } },
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(account.sip_channels.count).to eq(0)
      end

      it 'does not create a SIP voice inbox without the channel_voice feature' do
        post "/api/v1/accounts/#{account.id}/inboxes",
             headers: admin.create_new_auth_token,
             params: { name: 'PBX', channel: { type: 'voice', provider: 'sip', url: 'wss://pbx.example.com:8089/ws' } },
             as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(account.sip_channels.count).to eq(0)
      end

      it 'leaves the twilio number untouched when the inbox fails to save' do
        account.enable_features('channel_voice')
        account.save!
        stub_request(:get, %r{api\.twilio\.com/2010-04-01/Accounts/.*/IncomingPhoneNumbers\.json})
          .to_return(status: 200, body: { incoming_phone_numbers: [{ capabilities: { 'voice' => true } }] }.to_json,
                     headers: { 'Content-Type' => 'application/json' })
        allow(Twilio::VoiceWebhookSetupService).to receive(:new).and_return(instance_double(Twilio::VoiceWebhookSetupService,
                                                                                            perform: "AP#{SecureRandom.hex(16)}"))
        post "/api/v1/accounts/#{account.id}/inboxes",
             headers: admin.create_new_auth_token,
             params: { channel: { type: 'voice', phone_number: '+15551234567',
                                  provider_config: { account_sid: "AC#{SecureRandom.hex(16)}",
                                                     auth_token: SecureRandom.hex(16),
                                                     api_key_sid: SecureRandom.hex(8),
                                                     api_key_secret: SecureRandom.hex(16) } } },
             as: :json

        expect(response).not_to have_http_status(:success)
        # the rollback discarded the channel, so the number must not be left pointing at us
        expect(Channels::Twilio::WebhookSetupJob).not_to have_been_enqueued
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/inboxes/:id/set_inbound_calls' do
    before do
      allow(Twilio::VoiceWebhookSetupService).to receive(:new)
        .and_return(instance_double(Twilio::VoiceWebhookSetupService, perform: "AP#{SecureRandom.hex(16)}"))
    end

    context 'when administrator' do
      it 'disables inbound calls on a SIP voice inbox' do
        account.enable_features!('channel_voice')
        channel = create(:channel_sip, account: account)

        post "/api/v1/accounts/#{account.id}/inboxes/#{channel.inbox.id}/set_inbound_calls",
             headers: admin.create_new_auth_token,
             params: { inbound_calls_enabled: false },
             as: :json

        expect(response).to have_http_status(:ok)
        expect(channel.reload.inbound_calls_enabled?).to be false
      end

      it 'disables inbound calls on a Twilio voice inbox' do
        channel = create(:channel_twilio_sms, :with_voice, account: account)

        post "/api/v1/accounts/#{account.id}/inboxes/#{channel.inbox.id}/set_inbound_calls",
             headers: admin.create_new_auth_token,
             params: { inbound_calls_enabled: false },
             as: :json

        expect(response).to have_http_status(:ok)
        expect(channel.reload.inbound_calls_enabled?).to be false
      end

      it 'enables inbound calls on a WhatsApp inbox without re-validating provider config' do
        account.enable_features('channel_voice')
        account.save!
        channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                            validate_provider_config: false, sync_templates: false)
        channel.update!(provider_config: channel.provider_config.merge('calling_enabled' => true, 'inbound_calls_enabled' => false))

        post "/api/v1/accounts/#{account.id}/inboxes/#{channel.inbox.id}/set_inbound_calls",
             headers: admin.create_new_auth_token,
             params: { inbound_calls_enabled: true },
             as: :json

        expect(response).to have_http_status(:ok)
        expect(channel.reload.inbound_calls_enabled?).to be true
      end
    end

    context 'when agent' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'is forbidden' do
        channel = create(:channel_twilio_sms, :with_voice, account: account)

        post "/api/v1/accounts/#{account.id}/inboxes/#{channel.inbox.id}/set_inbound_calls",
             headers: agent.create_new_auth_token,
             params: { inbound_calls_enabled: false },
             as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(channel.reload.inbound_calls_enabled?).to be true
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/inboxes/:id/set_call_recording' do
    before do
      allow(Twilio::VoiceWebhookSetupService).to receive(:new)
        .and_return(instance_double(Twilio::VoiceWebhookSetupService, perform: "AP#{SecureRandom.hex(16)}"))
    end

    context 'when administrator' do
      it 'turns recording and transcription off on a Twilio voice inbox' do
        channel = create(:channel_twilio_sms, :with_voice, account: account)

        post "/api/v1/accounts/#{account.id}/inboxes/#{channel.inbox.id}/set_call_recording",
             headers: admin.create_new_auth_token,
             params: { recording_enabled: false, transcription_enabled: false },
             as: :json

        expect(response).to have_http_status(:ok)
        expect(channel.reload).to have_attributes(recording_enabled?: false, transcription_enabled?: false)
      end
    end

    context 'when the inbox has no calling' do
      it 'is rejected' do
        inbox = create(:inbox, account: account)

        post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/set_call_recording",
             headers: admin.create_new_auth_token,
             params: { recording_enabled: false, transcription_enabled: false },
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Inbox does not support calling')
      end
    end

    context 'when agent' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'is forbidden' do
        channel = create(:channel_twilio_sms, :with_voice, account: account)

        post "/api/v1/accounts/#{account.id}/inboxes/#{channel.inbox.id}/set_call_recording",
             headers: agent.create_new_auth_token,
             params: { recording_enabled: false, transcription_enabled: false },
             as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(channel.reload.recording_enabled?).to be true
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/inboxes/:id' do
    let(:inbox) { create(:inbox, account: account, auto_assignment_config: { max_assignment_limit: 5 }) }

    context 'when it is an authenticated user' do
      let(:admin) { create(:user, account: account, role: :administrator) }
      let(:valid_params) { { name: 'new test inbox', auto_assignment_config: { max_assignment_limit: 10 } } }

      it 'updates inbox with auto assignment config' do
        patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
              headers: admin.create_new_auth_token,
              params: valid_params,
              as: :json

        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)['auto_assignment_config']['max_assignment_limit']).to eq 10
      end
    end
  end
end
