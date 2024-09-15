# == Schema Information
#
# Table name: channel_notifica_me
#
#  id                             :bigint           not null, primary key
#  message_templates              :jsonb            not null
#  message_templates_last_updated :datetime
#  notifica_me_token              :string           not null
#  notifica_me_type               :string           not null
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  account_id                     :integer          not null
#  notifica_me_id                 :string           not null
#
# Indexes
#
#  index_channel_notifica_me  (notifica_me_id,account_id) UNIQUE
#

class Channel::NotificaMe < ApplicationRecord
  include Channelable

  self.table_name = 'channel_notifica_me'
  EDITABLE_ATTRS = [:notifica_me_id, :notifica_me_type, :notifica_me_token].freeze

  validates :notifica_me_id, presence: true
  validates :notifica_me_type, presence: true
  validates :notifica_me_token, presence: true
  validates :notifica_me_id, uniqueness: { scope: :account_id }

  def name
    'NotificaMe'
  end

  def whatsapp?
    notifica_me_type == 'whatsapp_business_account'
  end

  def mercado_livre?
    notifica_me_type == 'mercado_livre'
  end

  def notifica_me_path
    return 'whatsapp' if whatsapp?
    return 'mercadolivre' if  mercado_livre?

    notifica_me_type
  end

  def sync_templates
    url = "http://hub.notificame.com.br/v1/templates/#{notifica_me_id}"
    response = HTTParty.get(
      url,
      headers: {
        'X-API-Token' => notifica_me_token,
        'Content-Type' => 'application/json'
      },
      format: :json
    )
    templates = response.parsed_response['data'] || {}
    update(message_templates: templates, message_templates_last_updated: Time.now.utc) if templates.present?
  end
end
