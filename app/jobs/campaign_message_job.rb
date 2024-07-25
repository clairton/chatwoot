class CampaignMessageJob < ApplicationJob
  queue_as :high

  def perform(account_id, inbox_id, content, audience)
    phone_number = audience[:phone_number]
    contact = Contact.find_by(phone_number: phone_number, account_id: account_id)

    contact = Contact.create!(phone_number: phone_number, account_id: account_id) if contact.blank?

    contact_inbox = ContactInboxBuilder.new(
      contact: contact,
      inbox: Inbox.find(inbox_id),
      source_id: contact.phone_number.delete('+').to_s
    ).perform

    conversation = ConversationBuilder.new(params: {}, contact_inbox: contact_inbox).perform
    audience[:first_name] = audience[:name] || '' if audience[:name]

    m = content
    [:identifier, :first_name, :name, :due_at, :value, :scheduled_at].each do |f|
      k = f.to_sym
      m = m.gsub("##{f}", audience[k]) if audience[k]
    end

    Messages::MessageBuilder.new(nil, conversation, {
                                   content: m,
                                   message_type: :outgoing
                                 }).perform
  end
end
