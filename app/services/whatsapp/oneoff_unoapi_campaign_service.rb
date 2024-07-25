class Whatsapp::OneoffUnoapiCampaignService
  pattr_initialize [:campaign!]

  def perform
    raise "Invalid campaign #{campaign.id}" if inbox.inbox_type != 'Whatsapp' || channel.provider != 'unoapi' || !campaign.one_off?
    raise 'Completed Campaign' if campaign.completed?

    # marks campaign completed so that other jobs won't pick it up
    campaign.completed!

    process_audience(campaign.audience)
  end

  private

  delegate :inbox, to: :campaign
  delegate :channel, to: :inbox

  def process_audience(phone_numbers)
    phone_numbers.each do |phone_number|
      contact = Contact.find_by(phone_number: phone_number, account_id: campaign.account_id)

      contact = Contact.create!(phone_number: phone_number, account_id: campaign.account_id) if contact.blank?

      contact_inbox = ContactInboxBuilder.new(
        contact: contact,
        inbox: campaign.inbox,
        source_id: contact.phone_number.delete('+').to_s
      ).perform

      conversation = ConversationBuilder.new(params: {}, contact_inbox: contact_inbox).perform

      Messages::MessageBuilder.new(nil, conversation, {
                                     content: campaign.message,
                                     message_type: :outgoing
                                   }).perform
    end
  end
end
