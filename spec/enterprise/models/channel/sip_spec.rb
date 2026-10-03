require 'rails_helper'

RSpec.describe Channel::Sip do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_sip, account: account) }

  describe 'validations' do
    it 'requires a websocket url' do
      expect(build(:channel_sip, account: account, url: nil)).not_to be_valid
      expect(build(:channel_sip, account: account, url: 'https://pbx.example.com')).not_to be_valid
      expect(build(:channel_sip, account: account, url: 'ws://pbx.example.com:8088/ws')).to be_valid
    end
  end

  it 'generates a webhook token on create' do
    expect(channel.webhook_token).to be_present
  end

  it 'is named Sip' do
    expect(channel.name).to eq('Sip')
  end

  describe '#voice_enabled?' do
    it 'follows the channel_voice feature flag' do
      expect(channel.voice_enabled?).to be false

      account.enable_features!('channel_voice')

      expect(channel.reload.voice_enabled?).to be true
    end
  end

  describe '#inbound_calls_enabled?' do
    it 'defaults to on and only an explicit false turns it off' do
      expect(channel.inbound_calls_enabled?).to be true

      channel.update!(provider_config: { 'inbound_calls_enabled' => false })

      expect(channel.inbound_calls_enabled?).to be false
    end
  end

  it 'never records or transcribes, since media stays on the PBX' do
    expect(channel.recording_enabled?).to be false
    expect(channel.transcription_enabled?).to be false
  end
end
