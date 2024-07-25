class CampaignMessageJob < ApplicationJob
  queue_as :high
  retry_on ActiveRecord::RecordNotFound, wait: 30.seconds, attempts: 5

  def perform(account_id, inbox_id, phone_number, content)
    contact = Contact.find_by(phone_number: phone_number, account_id: account_id)

    contact = Contact.create!(phone_number: phone_number, account_id: account_id) if contact.blank?

    contact_inbox = ContactInboxBuilder.new(
      contact: contact,
      inbox: Inbox.find(inbox_id),
      source_id: contact.phone_number.delete('+').to_s
    ).perform

    conversation = ConversationBuilder.new(params: {}, contact_inbox: contact_inbox).perform

    Messages::MessageBuilder.new(nil, conversation, {
                                   content: content,
                                   message_type: :outgoing
                                 }).perform
  end
end
