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

      Contact.create!(phone_number: phone_number, account_id: account_id) if contact.blank?

      channel.send_message(to, content)
    end
  end
end
