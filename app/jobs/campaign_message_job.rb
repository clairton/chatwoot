class CampaignMessageJob < ApplicationJob
  queue_as :low

  # rubocop:disable Metrics/AbcSize
  def perform(account_id, inbox_id, campaign_id, content, audience)
    # rubocop:enable Metrics/AbcSize
    phone_number = audience[:phone_number]
    contact = Contact.find_by(phone_number: phone_number, account_id: account_id)
    contact = Contact.create!(phone_number: phone_number, account_id: account_id) if contact.blank?
    contact_inbox = ContactInboxBuilder.new(
      contact: contact, inbox: Inbox.find(inbox_id), source_id: contact.phone_number.delete('+').to_s
    ).perform
    conversation = ConversationBuilder.new(params: {}, contact_inbox: contact_inbox).perform
    audience[:first_name] = (audience[:name] || '').split[0]&.capitalize if audience[:name]
    m = content
    [:identifier, :first_name, :name, :due_at, :value, :scheduled_at].each do |f|
      k = f.to_sym
      m = m.gsub("##{f}", audience[k]) if audience[k]
    end
    conversation.messages.create!(
      content: m, account_id: account_id,
      content_type: :text, inbox_id: inbox_id,
      message_type: :outgoing, status: :progress,
      additional_attributes: { campaign_id: campaign_id, audience_id: audience[:audience_id] }
    )
  end
end
