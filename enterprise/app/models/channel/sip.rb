# == Schema Information
#
# Table name: channel_sip
#
#  id              :bigint           not null, primary key
#  phone_number    :string
#  provider_config :jsonb
#  url             :string           not null
#  webhook_token   :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#
# Indexes
#
#  index_channel_sip_on_account_id     (account_id)
#  index_channel_sip_on_webhook_token  (webhook_token) UNIQUE
#

# A voice-only channel backed by a SIP PBX. The PBX owns signalling and media: each agent's
# browser registers as an extension over the WebSocket in `url`, and the PBX reports call
# lifecycle events through the webhook identified by `webhook_token`.
class Channel::Sip < ApplicationRecord
  include Channelable

  self.table_name = 'channel_sip'

  EDITABLE_ATTRS = [:url, :phone_number].freeze
  WEBSOCKET_URL_REGEX = %r{\Awss?://\S+\z}

  has_secure_token :webhook_token

  validates :url, presence: true, length: { maximum: Limits::URL_LENGTH_LIMIT }, format: { with: WEBSOCKET_URL_REGEX }

  def name
    'Sip'
  end

  # Mirrors Channel::TwilioSms#voice_enabled? so the call subsystem can duck-type across providers.
  def voice_enabled?
    account.feature_enabled?('channel_voice')
  end

  # Mutes only the incoming side of calling; default on, so only an explicit false disables inbound.
  def inbound_calls_enabled?
    provider_config['inbound_calls_enabled'] != false
  end

  # Media flows between the browser and the PBX, so nothing reaches us to record or transcribe.
  def recording_enabled?
    false
  end

  def transcription_enabled?
    false
  end
end
