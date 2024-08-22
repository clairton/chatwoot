class CampaignMessageJob < ApplicationJob
  include Whatsapp::IncomingMessageServiceHelpers
  queue_as :low
  retry_on ActiveRecord::RecordNotFound, wait: 30.seconds, attempts: 5

  def perform(account_id, inbox_id, campaign_id, content, audience)
    contact_inbox = create_contact_inbox(inbox_id, audience)
    conversation = create_conversation(contact_inbox)
    conversation.messages.create!(
      content: bind(content, audience),
      account_id: account_id,
      content_type: :text,
      inbox_id: inbox_id,
      message_type: :outgoing,
      status: :progress,
      additional_attributes: {
        campaign_id: campaign_id,
        audience_id: audience[:audience_id]
      }
    )
  end

  private

  def bind(template, params)
    params[:first_name] = params[:name].split[0]&.capitalize if params[:name]
    [:identifier, :first_name, :name, :due_at, :value, :scheduled_at].reduce(template) do |content, field|
      params[field] ? content.gsub("##{field}", params[field]) : content
    end
  end

  def create_contact_inbox(inbox_id, params)
    phone_number = params[:phone_number].delete('+').to_s
    phone_number = brazil_phone_number?(phone_number) ? normalised_brazil_mobile_number(phone_number) : phone_number

    attributes = { name: params[:name], phone_number: "+#{phone_number}" }

    contact_inbox = ContactInboxWithContactBuilder.new(
      source_id: phone_number,
      inbox: Inbox.find(inbox_id),
      contact_attributes: attributes
    ).perform

    raise ActiveRecord::RecordNotFound if contact_inbox.nil?

    [:email, :identifier].each do |field|
      next if contact_inbox.contact[field] || !params[field]

      # rubocop:disable Rails/SkipsModelValidations
      begin
        contact_inbox.contact.update_column(field, params[field])
      rescue ActiveRecord::RecordNotUnique => e
        Rails.logger.warn("Ignore exception on campaign message job: #{e.message}")
      end
      # rubocop:enable Rails/SkipsModelValidations
    end

    contact_inbox
  end

  def create_conversation(contact_inbox)
    conversation = ConversationBuilder.new(params: { status: :resolved }, contact_inbox: contact_inbox).perform
    raise ActiveRecord::RecordNotFound if conversation.nil?

    conversation
  end
end
